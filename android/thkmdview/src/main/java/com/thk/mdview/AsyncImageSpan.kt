package com.thk.mdview

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.style.ReplacementSpan
import android.text.Spanned
import android.text.SpannableString
import android.widget.TextView
import android.view.View
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.min

/**
 * Renders a `![alt](url)` image inline in a text segment. Before the real bitmap is
 * known, it reserves a [maxWidthPx]-wide placeholder box (drawn as a rounded gray rect)
 * sized to a generic aspect ratio; once [attach]'s load completes, it re-measures itself
 * to the image's *real* aspect ratio (width capped at [maxWidthPx], height capped at
 * [absoluteMaxHeightPx]) and asks [View.requestLayout] to actually pick up the new size
 * - a real relayout, not just a redraw, since the box dimensions genuinely change once
 * the real dimensions are known. The image is always drawn flush with the span's own
 * box (left-aligned within the paragraph), never centered inside a wider reserved area.
 *
 * A fresh instance is created on every render pass (segments are rebuilt from
 * scratch), so [cancel] on the outgoing instance is what actually stops in-flight
 * I/O for a recycled-away view — the replacement instance never touches the old job.
 */
internal class AsyncImageSpan(
    val url: String,
    val altText: String,
    private val maxWidthPx: Int,
    private val absoluteMaxHeightPx: Int,
    private val cornerRadiusPx: Float,
    placeholderColor: Int
) : ReplacementSpan() {

    @Volatile private var bitmap: Bitmap? = null
    @Volatile private var currentWidthPx: Int = maxWidthPx
    @Volatile private var currentHeightPx: Int = (maxWidthPx * PLACEHOLDER_ASPECT_RATIO).toInt()
    private var loadJob: Job? = null
    private var hostView: View? = null

    private val placeholderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = placeholderColor }
    private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    /** Starts loading [url] on [scope], relaying out+invalidating [hostView] when the bitmap arrives. */
    fun attach(loader: THKImageLoader, scope: CoroutineScope, hostView: View) {
        this.hostView = hostView
        if (loadJob != null || bitmap != null) return
        loadJob = scope.launch {
            val loaded = loader.load(url) ?: return@launch
            val (width, height) = sizeRespectingRealAspectRatio(loaded.width, loaded.height)
            bitmap = if (width == loaded.width && height == loaded.height) {
                loaded
            } else {
                Bitmap.createScaledBitmap(loaded, width, height, true)
            }
            currentWidthPx = width
            currentHeightPx = height
            // requestLayout alone can reuse TextView's old Layout/line breaks.
            // Rebind the same spans (including this loaded bitmap) to invalidate it,
            // but never overwrite content if the host has already been recycled.
            if (hostView is TextView) {
                val text = hostView.text as? Spanned
                if (text != null && text.getSpanStart(this@AsyncImageSpan) >= 0) {
                    hostView.setText(SpannableString(text), TextView.BufferType.SPANNABLE)
                }
            }
            hostView.requestLayout()
            hostView.invalidate()
        }
    }

    fun cancel() {
        loadJob?.cancel()
        loadJob = null
    }

    override fun getSize(
        paint: Paint,
        text: CharSequence,
        start: Int,
        end: Int,
        fm: Paint.FontMetricsInt?
    ): Int {
        fm?.let {
            it.ascent = -currentHeightPx
            it.descent = 0
            it.top = it.ascent
            it.bottom = it.descent
        }
        return currentWidthPx
    }

    override fun draw(
        canvas: Canvas,
        text: CharSequence,
        start: Int,
        end: Int,
        x: Float,
        top: Int,
        y: Int,
        bottom: Int,
        paint: Paint
    ) {
        // Left-aligned with the paragraph: the box starts exactly at `x` (the span's own
        // position in the line), width/height always match the reported getSize() box -
        // never centered inside a separately-sized reservation.
        // getSize reserves space above the baseline, not above the line bottom
        // (which may include text descenders and paragraph spacing).
        val box = RectF(x, (y - currentHeightPx).toFloat(), x + currentWidthPx, y.toFloat())
        val bmp = bitmap
        if (bmp == null) {
            canvas.drawRoundRect(box, cornerRadiusPx, cornerRadiusPx, placeholderPaint)
            return
        }
        canvas.drawBitmap(bmp, null, box, bitmapPaint)
    }

    private fun sizeRespectingRealAspectRatio(sourceWidth: Int, sourceHeight: Int): Pair<Int, Int> {
        if (sourceWidth <= 0 || sourceHeight <= 0) return maxWidthPx to absoluteMaxHeightPx
        var width = min(sourceWidth, maxWidthPx)
        var height = (width.toLong() * sourceHeight / sourceWidth).toInt().coerceAtLeast(1)
        if (height > absoluteMaxHeightPx) {
            height = absoluteMaxHeightPx
            width = (height.toLong() * sourceWidth / sourceHeight).toInt().coerceAtLeast(1)
        }
        return width to height
    }

    private companion object {
        const val PLACEHOLDER_ASPECT_RATIO = 0.6f // height/width, used only before the real image loads
    }
}
