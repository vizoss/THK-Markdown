package com.thk.mdview

import android.graphics.Canvas
import android.graphics.Paint
import android.text.Layout
import android.text.Spanned
import android.text.style.BulletSpan
import kotlin.math.ceil

/** A font-scaled bullet, including on API 21 where BulletSpan has no radius API. */
internal class ThemedBulletSpan(
    val diameterPx: Float,
    private val gapPx: Int
) : BulletSpan(gapPx) {
    override fun getLeadingMargin(first: Boolean): Int = ceil(diameterPx).toInt() + gapPx

    override fun drawLeadingMargin(
        canvas: Canvas, paint: Paint, x: Int, dir: Int, top: Int, baseline: Int,
        bottom: Int, text: CharSequence, start: Int, end: Int, first: Boolean, layout: Layout?
    ) {
        // Do not repeat the marker on wrapped lines or subsequent paragraphs.
        if (!first || (text as? Spanned)?.getSpanStart(this) != start) return
        val oldStyle = paint.style
        val oldAntiAlias = paint.isAntiAlias
        try {
            paint.style = Paint.Style.FILL
            paint.isAntiAlias = true
            val radius = diameterPx / 2
            val metrics = paint.fontMetrics
            // Use the text baseline, not the entire line box (which can contain a
            // tall image, quote padding or additional paragraph spacing).
            val centerY = baseline + (metrics.ascent + metrics.descent) / 2
            canvas.drawCircle(x + dir * radius, centerY, radius, paint)
        } finally {
            paint.style = oldStyle
            paint.isAntiAlias = oldAntiAlias
        }
    }
}
