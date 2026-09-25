package com.thk.mdview

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Button

enum class THKSSEState { IDLE, WAITING, STREAMING, COMPLETED, STOPPED, FAILED }
data class THKSSEIndicatorStyle(val color: Int? = null, val diameterDp: Float = 6f, val gapDp: Float = 5f, val cycleMs: Long = 900)
enum class THKRenderFailureStage { INCREMENTAL, FULL }
data class THKRenderFailure(val stage: THKRenderFailureStage, val cause: Exception)

internal class SSEDots(context: Context) : View(context) {
    var style = THKSSEIndicatorStyle()
        set(value) { field = value; animator?.duration = value.cycleMs.coerceAtLeast(300) }
    var color = android.graphics.Color.GRAY
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var phase = 0f
    private var animator: ValueAnimator? = null
    fun animateDots(active: Boolean) {
        if (!active) { animator?.cancel(); animator = null; return }
        if (animator != null) return
        animator = ValueAnimator.ofFloat(0f, 3f).apply {
            duration = style.cycleMs.coerceAtLeast(300)
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener { phase = it.animatedValue as Float; invalidate() }
            start()
        }
    }
    override fun onDraw(canvas: Canvas) {
        val density = resources.displayMetrics.density
        val radius = style.diameterDp.coerceIn(2f, 20f) * density / 2
        val step = radius * 2 + style.gapDp.coerceIn(0f, 20f) * density
        paint.color = color
        repeat(3) { i ->
            val distance = kotlin.math.abs(phase - i).let { minOf(it, 3 - it) }
            paint.alpha = (255 * (0.25f + 0.75f * (1 - distance).coerceAtLeast(0f))).toInt()
            canvas.drawCircle(radius + i * step, height / 2f, radius, paint)
        }
    }
}

internal class SSEFooter(context: Context) : LinearLayout(context) {
    private val dots = SSEDots(context)
    private val message = TextView(context)
    private val retry = Button(context).apply {
        text = "重试"; isAllCaps = false
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        setPadding(0, 0, 0, 0)
        gravity = android.view.Gravity.START or android.view.Gravity.CENTER_VERTICAL
        minHeight = (44 * resources.displayMetrics.density).toInt()
    }
    private var indicator: View = dots
    private var busy = false
    private var running = false
    var onActivity: ((View, Boolean) -> Unit)? = null
    init { orientation = VERTICAL; visibility = GONE }
    fun configure(state: THKSSEState, enabled: Boolean, custom: View?, style: THKSSEIndicatorStyle,
                  theme: THKMDTheme, error: String?, onRetry: (() -> Unit)?) {
        val next = custom ?: dots
        if (next !== indicator) {
            stop()
            require(next.parent == null || next.parent === this) { "SSE indicator already belongs to another parent" }
            removeAllViews(); indicator = next
        }
        dots.style = style; dots.color = style.color ?: theme.bodyTextColor; dots.invalidate()
        busy = enabled && state in listOf(THKSSEState.WAITING, THKSSEState.STREAMING)
        val failed = enabled && state == THKSSEState.FAILED
        if (busy) {
            if (indicator.parent == null) {
                removeAllViews()
                addView(indicator, LayoutParams(LayoutParams.MATCH_PARENT,
                    if (indicator === dots) (24 * resources.displayMetrics.density).toInt() else LayoutParams.WRAP_CONTENT))
            }
            indicator.contentDescription = if (state == THKSSEState.WAITING) "思考中" else "正在输出"
        } else if (failed) {
            stop(); removeAllViews()
            message.text = error?.takeIf { it.isNotBlank() } ?: "回复失败，请重试"
            message.setTextColor(theme.bodyTextColor); message.textSize = theme.bodyFontSizeSp
            retry.setTextColor(theme.linkColor); retry.textSize = theme.bodyFontSizeSp
            addView(message)
            if (onRetry != null) { retry.setOnClickListener { onRetry() }; addView(retry) }
        }
        visibility = if (busy || failed) VISIBLE else GONE
        refresh()
    }
    private fun stop() {
        dots.animateDots(false)
        if (running) { running = false; onActivity?.invoke(indicator, false) }
    }
    fun refresh() {
        val next = busy && isAttachedToWindow && isShown && windowVisibility == VISIBLE
        if (!next) { stop(); return }
        if (!running) { running = true; if (indicator === dots) dots.animateDots(true); onActivity?.invoke(indicator, true) }
    }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); refresh() }
    override fun onDetachedFromWindow() { stop(); super.onDetachedFromWindow() }
    override fun onWindowVisibilityChanged(visibility: Int) { super.onWindowVisibilityChanged(visibility); if (childCount > 0) refresh() }
    override fun onVisibilityChanged(changedView: View, visibility: Int) { super.onVisibilityChanged(changedView, visibility); if (childCount > 0) refresh() }
}
