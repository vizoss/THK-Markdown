package com.thk.mdview

import android.os.Handler
import android.os.Looper

class StreamingMarkdownBuffer(
    var debounceMs: Long = 32L,
    private val handler: Handler = Handler(Looper.getMainLooper()),
    private val onRender: (String) -> Unit
) {
    private val raw = StringBuilder()
    private var pendingRender: Runnable? = null
    internal val hasPendingRender: Boolean get() = pendingRender != null

    val currentText: String
        get() = raw.toString()

    fun setFull(markdown: String) {
        cancelPending()
        raw.setLength(0)
        raw.append(markdown)
        onRender(raw.toString())
    }

    fun append(chunk: String) {
        raw.append(chunk)
        scheduleRender()
    }

    fun reset() {
        cancelPending()
        raw.setLength(0)
    }

    private fun scheduleRender() {
        // Cancel-then-reschedule on every append is what makes N rapid chunks inside
        // one debounce window coalesce into a single render pass.
        cancelPending()
        val runnable = Runnable {
            pendingRender = null
            onRender(raw.toString())
        }
        pendingRender = runnable
        handler.postDelayed(runnable, debounceMs)
    }

    internal fun cancelPending() {
        // Must run inside reset() (and before every reschedule) so a recycled-away
        // RecyclerView item's stale render can never land on the view that replaced it.
        pendingRender?.let { handler.removeCallbacks(it) }
        pendingRender = null
    }
}
