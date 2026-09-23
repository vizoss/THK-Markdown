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
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job

/**
 * A minimal LLM chat UI: type a message, get a (mocked) assistant reply that
 * streams back in over simulated SSE chunks via [ChatAdapter]/[THKMDView].
 */
class MainActivity : AppCompatActivity() {

    private var nextMessageId = 0L
    private lateinit var adapter: ChatAdapter
    private lateinit var recyclerView: RecyclerView
    private var followsLatestMessage = true
    private lateinit var fixtures: List<MarkdownFixture>
    private var selectedFixture = 0
    private var playback: Job? = null
    private var playbackMessageId: Long? = null
    private var chunkIndex = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<Button>(R.id.themeButton).setOnClickListener {
            ThemeSettingsSheet.show(supportFragmentManager, adapter.theme) {
                adapter.setTheme(it)
                DemoThemeStore.save(this, it)
            }
        }

        recyclerView = findViewById(R.id.messageList)
        adapter = ChatAdapter(onAssistantContentUpdated = ::scrollToBottom)
        adapter.setTheme(DemoThemeStore.load(this))
        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.setHasFixedSize(false)
        recyclerView.adapter = adapter
        recyclerView.itemAnimator = null
        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(rv: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_DRAGGING) followsLatestMessage = false
                if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    followsLatestMessage = !rv.canScrollVertically(1)
                }
            }
        })

fixtures = try { MarkdownFixture.loadAll(this) } catch (error: Exception) {
            AlertDialog.Builder(this).setTitle("用例加载失败").setMessage(error.toString()).setPositiveButton("关闭", null).show()
            return
        }
        installFixtureControls()
        showFixture(full = true)
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

    private fun sendMessage(messageInput: EditText) {
        val text = messageInput.text?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return
        messageInput.text?.clear()

        followsLatestMessage = true
        adapter.addMessage(ChatMessage(nextMessageId++, Role.USER, text))
        scrollToBottom()

        // User input remains a separate bubble; it never changes the fixture Markdown.
        showFixture(full = false, clearHistory = false)
        playFixture()
    }

    private fun installFixtureControls() {
        findViewById<Button>(R.id.selectFixture).setOnClickListener {
            selectFixtureGroup()
        }
        findViewById<Button>(R.id.fixturePrevious).setOnClickListener {
            val previous = previousFixtureIndex() ?: return@setOnClickListener
            selectedFixture = previous
            showFixture(full = true)
        }
        findViewById<Button>(R.id.fixtureNext).setOnClickListener {
            val next = nextFixtureIndex() ?: return@setOnClickListener
            selectedFixture = next
            showFixture(full = true)
        }
        findViewById<Button>(R.id.fixtureFull).setOnClickListener { showFixture(full = true) }
        findViewById<Button>(R.id.fixturePlay).setOnClickListener { playFixture() }
        findViewById<Button>(R.id.fixturePause).setOnClickListener {
            playback?.cancel(); playback = null; updateFixtureStatus("已暂停")
        }
        findViewById<Button>(R.id.fixtureStep).setOnClickListener {
            playback?.cancel(); playback = null
            if (chunkIndex >= fixtures[selectedFixture].chunks.size) showFixture(full = false)
            advanceFixture()
        }
        findViewById<TextView>(R.id.fixtureStatus).setOnClickListener {
            val fixture = fixtures[selectedFixture]
            DemoDialog.show(this, fixture.id + " · " + fixture.title,
                body = "验收要求\n" + fixture.summary + "\n\nMarkdown 原文\n" + fixture.markdown)
        }
    }

    private fun selectFixtureGroup() {
        val groups = listOf("P0", "P1", "P2")
        val currentID = fixtures.getOrNull(selectedFixture)?.id
        DemoDialog.show(this, "Markdown 用例", choices = groups.map { group ->
            "$group · ${fixtures.count { it.id.startsWith("$group-") }} 个用例  ›"
        }, selected = groups.indexOfFirst { currentID?.startsWith("$it-") == true }) { index ->
            selectFixtureInGroup(groups[index])
        }
    }

    private fun selectFixtureInGroup(group: String) {
        // Keep catalog indices: selecting P1 must not accidentally select a P0 row.
        val indices = fixtures.indices.filter { fixtures[it].id.startsWith("$group-") }
        val current = indices.indexOf(selectedFixture)
        DemoDialog.show(this, "$group 用例",
            choices = listOf("‹ 返回分组") + indices.map { "${fixtures[it].id} · ${fixtures[it].title}" },
            selected = if (current >= 0) current + 1 else -1) { row ->
            if (row == 0) {
                selectFixtureGroup()
            } else {
                selectedFixture = indices[row - 1]
                showFixture(full = true)
            }
        }
    }

    private fun showFixture(full: Boolean, clearHistory: Boolean = true) {
        playback?.cancel(); playback = null
        val fixture = fixtures[selectedFixture]
        if (clearHistory) {
            adapter.clearMessages()
            fixture.history.forEach { adapter.addMessage(ChatMessage(nextMessageId++, Role.ASSISTANT, it)) }
        }
        val id = nextMessageId++
        playbackMessageId = id
        chunkIndex = if (full) fixture.chunks.size else 0
        adapter.addMessage(ChatMessage(id, Role.ASSISTANT, if (full) fixture.markdown else ""))
        followsLatestMessage = true
        findViewById<Button>(R.id.selectFixture).text = "${fixture.id} · ${fixture.title} ▾"
        updateFixtureStatus(if (full) "全文" else "待播放")
        scrollToBottom()
    }

    private fun playFixture() {
        playback?.cancel()
        if (chunkIndex >= fixtures[selectedFixture].chunks.size) showFixture(full = false)
        playback = lifecycleScope.launch {
            while (chunkIndex < fixtures[selectedFixture].chunks.size) {
                advanceFixture()
                delay(500L)
            }
            updateFixtureStatus("已完成")
        }
    }

    private fun advanceFixture() {
        val fixture = fixtures[selectedFixture]
        val id = playbackMessageId ?: return
        if (chunkIndex < fixture.chunks.size) adapter.appendChunk(id, fixture.chunks[chunkIndex++])
        updateFixtureStatus(if (chunkIndex == fixture.chunks.size) "已完成" else "逐步渲染")
    }

    private fun previousFixtureIndex(): Int? {
        if (selectedFixture !in fixtures.indices) return null
        return (selectedFixture - 1).takeIf { it in fixtures.indices }
    }

    private fun nextFixtureIndex(): Int? {
        if (selectedFixture !in fixtures.indices) return null
        return (selectedFixture + 1).takeIf { it in fixtures.indices }
    }

    private fun updateFixtureStatus(state: String) {
        findViewById<Button>(R.id.fixturePrevious).apply {
            isEnabled = previousFixtureIndex() != null
            setTextColor(androidx.core.content.ContextCompat.getColor(this@MainActivity,
                if (isEnabled) R.color.demo_ink else R.color.demo_muted))
        }
        findViewById<Button>(R.id.fixtureNext).apply {
            isEnabled = nextFixtureIndex() != null
            setTextColor(androidx.core.content.ContextCompat.getColor(this@MainActivity,
                if (isEnabled) R.color.demo_ink else R.color.demo_muted))
        }
        findViewById<TextView>(R.id.fixtureStatus).text = "$state · $chunkIndex/${fixtures[selectedFixture].chunks.size} 分片 · 点击查看原文与验收要求"
    }

    private fun scrollToBottom() {
        // Render is debounced; follow only after its new height has reached layout.
        recyclerView.removeCallbacks(followLatest)
        if (followsLatestMessage) recyclerView.postDelayed(followLatest, 40L)
    }

    private val followLatest = Runnable {
        if (followsLatestMessage && recyclerView.scrollState == RecyclerView.SCROLL_STATE_IDLE) {
            val manager = recyclerView.layoutManager as LinearLayoutManager
            val last = manager.findViewByPosition(adapter.itemCount - 1)
            if (last != null) {
                recyclerView.scrollBy(0, maxOf(0, manager.getDecoratedBottom(last) -
                    (recyclerView.height - recyclerView.paddingBottom)))
            } else if (adapter.itemCount > 0) {
                manager.scrollToPositionWithOffset(adapter.itemCount - 1, 0)
                recyclerView.post { if (followsLatestMessage) scrollToBottom() }
            }
        }
    }
}
