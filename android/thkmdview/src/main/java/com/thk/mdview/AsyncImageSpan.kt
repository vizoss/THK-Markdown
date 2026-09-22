package com.thk.mdview

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.style.ReplacementSpan
import android.view.View
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.min

/**
 * Renders a `![alt](url)` image inline in a text segment: reserves a fixed
 * [maxWidthPx] x [maxHeightPx] placeholder box (drawn as a rounded gray rect) so the
 * surrounding text never relays out, then swaps in the real bitmap once [attach]'s
 * load completes, scaled to fit the box without changing its size.
 *
 * A fresh instance is created on every render pass (segments are rebuilt from
 * scratch), so [cancel] on the outgoing instance is what actually stops in-flight
 * I/O for a recycled-away view — the replacement instance never touches the old job.
 */
internal class AsyncImageSpan(
    val url: String,
    val altText: String,
    private val maxWidthPx: Int,
    private val maxHeightPx: Int,
    private val cornerRadiusPx: Float,
    placeholderColor: Int
) : ReplacementSpan() {

    @Volatile private var bitmap: Bitmap? = null
    @Volatile private var drawWidth: Int = maxWidthPx
    @Volatile private var drawHeight: Int = maxHeightPx
    private var loadJob: Job? = null

    private val placeholderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = placeholderColor }
    private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    /** Starts loading [url] on [scope], invalidating [hostView] when the bitmap arrives. */
    fun attach(loader: THKImageLoader, scope: CoroutineScope, hostView: View) {
        if (loadJob != null || bitmap != null) return
        loadJob = scope.launch {
            val loaded = loader.load(url) ?: return@launch
            val fitted = scaleToFit(loaded, maxWidthPx, maxHeightPx)
            bitmap = fitted.first
            drawWidth = fitted.second
            drawHeight = fitted.third
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
            it.ascent = -maxHeightPx
            it.descent = 0
            it.top = it.ascent
            it.bottom = it.descent
        }
        return maxWidthPx
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
        val box = RectF(x, (bottom - maxHeightPx).toFloat(), x + maxWidthPx, bottom.toFloat())
        val bmp = bitmap
        if (bmp == null) {
            canvas.drawRoundRect(box, cornerRadiusPx, cornerRadiusPx, placeholderPaint)
            return
        }
        val dstLeft = box.left + (box.width() - drawWidth) / 2f
        val dstTop = box.top + (box.height() - drawHeight) / 2f
        val dst = RectF(dstLeft, dstTop, dstLeft + drawWidth, dstTop + drawHeight)
        canvas.drawBitmap(bmp, null, dst, bitmapPaint)
    }

    private fun scaleToFit(source: Bitmap, maxW: Int, maxH: Int): Triple<Bitmap, Int, Int> {
        val scale = min(maxW.toFloat() / source.width, maxH.toFloat() / source.height).coerceAtMost(1f)
        val w = (source.width * scale).toInt().coerceAtLeast(1)
        val h = (source.height * scale).toInt().coerceAtLeast(1)
        val scaled = if (scale >= 1f) source else Bitmap.createScaledBitmap(source, w, h, true)
        return Triple(scaled, w, h)
    }
}
