package com.thk.mdview.sample

import android.content.Context
import android.os.Bundle
import android.view.GestureDetector
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random
import kotlin.time.Duration.Companion.milliseconds

/**
 * A minimal LLM chat UI: type a message, get a (mocked) assistant reply that
 * streams back in over simulated SSE chunks via [ChatAdapter]/[THKMDView].
 */
class MainActivity : AppCompatActivity() {

    private var nextMessageId = 0L
    private lateinit var adapter: ChatAdapter
    private lateinit var recyclerView: RecyclerView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        setSupportActionBar(findViewById<Toolbar>(R.id.toolbar))

        recyclerView = findViewById(R.id.messageList)
        adapter = ChatAdapter(onAssistantContentUpdated = ::scrollToBottom)
        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.setHasFixedSize(false)
        recyclerView.adapter = adapter

        adapter.addMessage(ChatMessage(nextMessageId++, Role.ASSISTANT, GREETING_MARKDOWN))
        installKeyboardDismissOnTap()

        val messageInput = findViewById<EditText>(R.id.messageInput)
        val sendButton = findViewById<Button>(R.id.sendButton)

        sendButton.setOnClickListener { sendMessage(messageInput) }
        messageInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                sendMessage(messageInput)
                true
            } else {
                false
            }
        }
    }

    // IM-style keyboard dismissal: a genuine *tap* on the message list dismisses the
    // keyboard; a *scroll*/drag through the list does not. The previous implementation
    // hooked Activity.dispatchTouchEvent on every ACTION_DOWN, which can't tell a tap
    // from the start of a drag - it dismissed the keyboard the instant a scroll gesture
    // began, making the list nearly unusable with the keyboard open. A GestureDetector
    // wired through RecyclerView.OnItemTouchListener (observing, never intercepting -
    // onInterceptTouchEvent always returns false here) gets a callback only once a tap is
    // actually *confirmed* (down+up with no meaningful movement), while RecyclerView's own
    // touch handling independently and unaffectedly drives scrolling/flinging. Only the
    // list is wired this way - not the whole Activity - so tapping the Send button (part
    // of the separate input bar, not the RecyclerView) never dismisses the keyboard as a
    // side effect, matching real IM apps where sending keeps the keyboard up so you can
    // keep typing.
    private fun installKeyboardDismissOnTap() {
        val detector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapUp(e: MotionEvent): Boolean {
                dismissKeyboard()
                return false
            }
        })
        recyclerView.addOnItemTouchListener(object : RecyclerView.SimpleOnItemTouchListener() {
            override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
                detector.onTouchEvent(e)
                return false
            }
        })
    }

    private fun dismissKeyboard() {
        val focused = currentFocus ?: return
        focused.clearFocus()
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(focused.windowToken, 0)
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.menu_main, menu)
        return true
    }

    // Opens the live-editable theme settings sheet instead of just toggling between two
    // hardcoded presets. Every control in the sheet still funnels through
    // ChatAdapter.setTheme below - the same mechanism that proves THKMDView.theme = ...
    // alone re-renders already-bound bubbles, with no reset()/setMarkdown call involved.
    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId == R.id.action_theme) {
            ThemeSettingsSheet.show(supportFragmentManager, adapter.theme) { theme ->
                adapter.setTheme(theme)
            }
            return true
        }
        return super.onOptionsItemSelected(item)
    }

    private fun sendMessage(messageInput: EditText) {
        val text = messageInput.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return
        messageInput.text?.clear()

        adapter.addMessage(ChatMessage(nextMessageId++, Role.USER, text))
        scrollToBottom()

        lifecycleScope.launch {
            delay(Random.nextLong(400L, 900L).milliseconds) // simulated "assistant is thinking" latency
            adapter.addMessage(ChatMessage(nextMessageId++, Role.ASSISTANT, buildMockAssistantReply(text)))
            scrollToBottom()
        }
    }

    private fun scrollToBottom() {
        val lastPosition = adapter.itemCount - 1
        if (lastPosition >= 0) {
            recyclerView.scrollToPosition(lastPosition)
        }
    }
}
