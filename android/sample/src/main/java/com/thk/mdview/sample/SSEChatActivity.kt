package com.thk.mdview.sample

import android.content.Context
import android.os.Bundle
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Local simulated SSE, identical fixture sequence/chunk delay to the iOS chat. */
class SSEChatActivity : DemoPageActivity() {
    private lateinit var adapter: ChatAdapter
    private lateinit var list: RecyclerView
    private var fixtures: List<MarkdownFixture> = emptyList()
    private var replyIndex = 0
    private var nextID = 0L
    private var playback: Job? = null
    private var followsLatest = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_sse_chat)
        installHeader("SSE Chat")
        list = findViewById(R.id.messageList)
        adapter = ChatAdapter(::scrollToBottom)
        list.layoutManager = LinearLayoutManager(this)
        list.adapter = adapter
        list.itemAnimator = null
        list.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(rv: RecyclerView, state: Int) {
                if (state == RecyclerView.SCROLL_STATE_DRAGGING) followsLatest = false
                if (state == RecyclerView.SCROLL_STATE_IDLE) followsLatest = !rv.canScrollVertically(1)
            }
        })
        val detector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapUp(e: MotionEvent): Boolean {
                currentFocus?.let { focus ->
                    focus.clearFocus()
                    (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(focus.windowToken, 0)
                }
                return false
            }
        })
        list.addOnItemTouchListener(object : RecyclerView.SimpleOnItemTouchListener() {
            override fun onInterceptTouchEvent(rv: RecyclerView, event: MotionEvent): Boolean { detector.onTouchEvent(event); return false }
        })
        fixtures = runCatching { MarkdownFixture.loadAll(this) }.getOrElse {
            findViewById<TextView>(R.id.chatStatus).text = "用例加载失败：${it.message}"
            emptyList()
        }
        val input = findViewById<EditText>(R.id.messageInput)
        findViewById<Button>(R.id.sendButton).setOnClickListener { send(input) }
        input.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_SEND) { send(input); true } else false
        }
    }

    override fun onResume() { super.onResume(); adapter.setTheme(DemoThemeStore.load(this)) }

    override fun onDestroy() {
        adapter.clearMessages()
        list.adapter = null
        super.onDestroy()
    }

    private fun send(input: EditText) {
        val text = input.text.toString().trim()
        if (text.isEmpty() || fixtures.isEmpty()) return
        input.text.clear()
        playback?.cancel()
        followsLatest = true
        adapter.addMessage(ChatMessage(nextID++, Role.USER, text))
        val fixture = fixtures[replyIndex++ % fixtures.size]
        val id = nextID++
        adapter.addMessage(ChatMessage(id, Role.ASSISTANT, ""))
        playback = lifecycleScope.launch {
            fixture.chunks.forEachIndexed { index, chunk ->
                adapter.appendChunk(id, chunk)
                findViewById<TextView>(R.id.chatStatus).text = "模拟 SSE · ${fixture.id} · ${index + 1}/${fixture.chunks.size} 分片"
                scrollToBottom()
                delay(500)
            }
            playback = null
            findViewById<TextView>(R.id.chatStatus).text = "模拟 SSE · ${fixture.id} · 已完成"
        }
        scrollToBottom()
    }

    private fun scrollToBottom() { list.removeCallbacks(followLatest); if (followsLatest) list.postDelayed(followLatest, 40) }
    private val followLatest = Runnable {
        if (followsLatest && list.scrollState == RecyclerView.SCROLL_STATE_IDLE && adapter.itemCount > 0) {
            val manager = list.layoutManager as LinearLayoutManager
            val last = manager.findViewByPosition(adapter.itemCount - 1)
            if (last != null) list.scrollBy(0, maxOf(0, manager.getDecoratedBottom(last) - (list.height - list.paddingBottom)))
            else { manager.scrollToPositionWithOffset(adapter.itemCount - 1, 0); list.post { if (followsLatest) scrollToBottom() } }
        }
    }

    override fun onStop() {
        if (playback != null) findViewById<TextView>(R.id.chatStatus).text = "模拟 SSE · 已停止，已接收内容保留"
        playback?.cancel(); playback = null
        list.removeCallbacks(followLatest)
        super.onStop()
    }
}
