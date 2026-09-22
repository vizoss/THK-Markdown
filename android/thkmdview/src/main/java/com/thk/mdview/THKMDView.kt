package com.thk.mdview

import android.content.Context
import android.text.method.LinkMovementMethod
import android.util.AttributeSet
import androidx.appcompat.widget.AppCompatTextView

class THKMDView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : AppCompatTextView(context, attrs) {

    var streamingDebounceMs: Long = 32L
        set(value) {
            field = value
            buffer.debounceMs = value
        }

    var onLinkClick: ((String) -> Boolean)? = null

    private var renderer: MarkdownRenderer =
        DefaultMarkdownRenderer(linkHandler = { url -> onLinkClick?.invoke(url) == true })

    private val buffer = StreamingMarkdownBuffer(debounceMs = streamingDebounceMs) { markdown ->
        renderNow(markdown)
    }

    init {
        movementMethod = LinkMovementMethod.getInstance()
    }

    fun setMarkdown(markdown: String) {
        buffer.setFull(markdown)
    }

    fun appendMarkdownChunk(chunk: String) {
        buffer.append(chunk)
    }

    // Safe to call from onViewRecycled: cancels any pending debounced render and
    // clears the buffer so a stale delta can never land on a reused item.
    fun reset() {
        buffer.reset()
        text = ""
    }

    fun setMarkdownRenderer(renderer: MarkdownRenderer) {
        this.renderer = renderer
        renderNow(buffer.currentText)
    }

    private fun renderNow(markdown: String) {
        text = renderer.render(markdown)
    }
}
