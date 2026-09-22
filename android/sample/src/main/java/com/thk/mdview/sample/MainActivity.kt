package com.thk.mdview.sample

import android.content.Context
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.thk.mdview.THKMDTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

/**
 * A minimal LLM chat UI: type a message, get a (mocked) assistant reply that
 * streams back in over simulated SSE chunks via [ChatAdapter]/[THKMDView].
 */
class MainActivity : AppCompatActivity() {

    private var nextMessageId = 0L
    private var usingAltTheme = false
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

    // Tapping anywhere that isn't the currently-focused EditText (including taps that
    // land on THKMDView but aren't a link/image, which don't consume the touch) dismisses
    // the keyboard - a side effect only, never consumes the event, so scrolling/links/
    // buttons underneath still work exactly as before.
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.action == MotionEvent.ACTION_DOWN) {
            val focused = currentFocus
            if (focused is EditText && !isTouchInsideView(focused, ev)) {
                focused.clearFocus()
                val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                imm.hideSoftInputFromWindow(focused.windowToken, 0)
            }
        }
        return super.dispatchTouchEvent(ev)
    }

    private fun isTouchInsideView(view: View, event: MotionEvent): Boolean {
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        val x = event.rawX.toInt()
        val y = event.rawY.toInt()
        return x in location[0]..(location[0] + view.width) && y in location[1]..(location[1] + view.height)
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.menu_main, menu)
        return true
    }

    // Proves THKMDView.theme = ... alone re-renders already-bound bubbles: no
    // reset()/setMarkdown call happens here, only ChatAdapter.setTheme below.
    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId == R.id.action_theme) {
            usingAltTheme = !usingAltTheme
            adapter.setTheme(if (usingAltTheme) ALT_THEME else THKMDTheme.Default)
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
            delay(Random.nextLong(400L, 900L)) // simulated "assistant is thinking" latency
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
