package com.thk.mdview.sample

import android.os.Bundle
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import androidx.appcompat.app.AppCompatActivity
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

        recyclerView = findViewById(R.id.messageList)
        adapter = ChatAdapter(onAssistantContentUpdated = ::scrollToBottom)
        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.setHasFixedSize(false)
        recyclerView.adapter = adapter

        adapter.addMessage(ChatMessage(nextMessageId++, Role.ASSISTANT, GREETING_MARKDOWN))

        val messageInput = findViewById<EditText>(R.id.messageInput)
        val sendButton = findViewById<Button>(R.id.sendButton)
        val themeToggleButton = findViewById<Button>(R.id.themeToggleButton)

        sendButton.setOnClickListener { sendMessage(messageInput) }
        messageInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                sendMessage(messageInput)
                true
            } else {
                false
            }
        }
        // Proves THKMDView.theme = ... alone re-renders already-bound bubbles: no
        // reset()/setMarkdown call happens here, only ChatAdapter.setTheme below.
        themeToggleButton.setOnClickListener {
            usingAltTheme = !usingAltTheme
            adapter.setTheme(if (usingAltTheme) ALT_THEME else THKMDTheme.Default)
        }
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
