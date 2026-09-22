package com.thk.mdview

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.Layout
import android.text.style.ClickableSpan
import android.text.style.LeadingMarginSpan
import android.text.style.LineBackgroundSpan
import android.view.View

internal class LinkClickableSpan(
    private val url: String,
    private val handler: (String) -> Boolean
) : ClickableSpan() {
    override fun onClick(widget: View) {
        handler(url)
    }
}

// Draws a full rounded-rect background across a (possibly multi-line) code block: each
// line only gets the flat middle-fill, except the block's first line (rounded top
// corners) and last line (rounded bottom corners) - drawn as a full round-rect then
// squared off on the far side, which is cheaper than tracking per-glyph paths.
internal class CodeBlockBackgroundSpan(
    private val backgroundColor: Int,
    private val cornerRadiusPx: Float,
    private val spanStart: Int,
    private val spanEnd: Int
) : LineBackgroundSpan {
    override fun drawBackground(
        canvas: Canvas,
        paint: Paint,
        left: Int,
        right: Int,
        top: Int,
        baseline: Int,
        bottom: Int,
        text: CharSequence,
        start: Int,
        end: Int,
        lineNumber: Int
    ) {
        val isFirstLine = start <= spanStart
        val isLastLine = end >= spanEnd
        val rect = RectF(left.toFloat(), top.toFloat(), right.toFloat(), bottom.toFloat())
        val originalColor = paint.color
        paint.color = backgroundColor
        when {
            isFirstLine && isLastLine -> canvas.drawRoundRect(rect, cornerRadiusPx, cornerRadiusPx, paint)
            isFirstLine -> {
                canvas.drawRoundRect(rect, cornerRadiusPx, cornerRadiusPx, paint)
                canvas.drawRect(rect.left, rect.top + cornerRadiusPx, rect.right, rect.bottom, paint)
            }
            isLastLine -> {
                canvas.drawRoundRect(rect, cornerRadiusPx, cornerRadiusPx, paint)
                canvas.drawRect(rect.left, rect.top, rect.right, rect.bottom - cornerRadiusPx, paint)
            }
            else -> canvas.drawRect(rect, paint)
        }
        paint.color = originalColor
    }
}

// Adds left inset inside a code block's background so text doesn't touch the rounded
// edge; a plain LeadingMarginSpan with no drawing, purely for the padding.
internal class CodeBlockPaddingSpan(private val paddingPx: Int) : LeadingMarginSpan {
    override fun getLeadingMargin(first: Boolean): Int = paddingPx
    override fun drawLeadingMargin(
        canvas: Canvas, paint: Paint, x: Int, dir: Int, top: Int, baseline: Int, bottom: Int,
        text: CharSequence, start: Int, end: Int, first: Boolean, layout: Layout?
    ) = Unit
}

// A LeadingMarginSpan-based block-quote bar (rather than android.text.style.QuoteSpan,
// whose colored constructor needs API 28): multiple instances stacked over the same
// range - one per nesting level - render as multiple side-by-side bars for `> > nested`.
internal class ThemedQuoteSpan(
    private val barColor: Int,
    private val stripeWidthPx: Int = 6,
    private val gapWidthPx: Int = 20
) : LeadingMarginSpan {
    override fun getLeadingMargin(first: Boolean): Int = stripeWidthPx + gapWidthPx

    override fun drawLeadingMargin(
        canvas: Canvas,
        paint: Paint,
        x: Int,
        dir: Int,
        top: Int,
        baseline: Int,
        bottom: Int,
        text: CharSequence,
        start: Int,
        end: Int,
        first: Boolean,
        layout: Layout?
    ) {
        val originalColor = paint.color
        val originalStyle = paint.style
        paint.color = barColor
        paint.style = Paint.Style.FILL
        canvas.drawRect(
            (x).toFloat(),
            top.toFloat(),
            (x + dir * stripeWidthPx).toFloat(),
            bottom.toFloat(),
            paint
        )
        paint.color = originalColor
        paint.style = originalStyle
    }
}

internal class OrderedListItemSpan(
    private val number: Int,
    private val gapWidth: Int
) : LeadingMarginSpan {

    override fun getLeadingMargin(first: Boolean): Int = gapWidth + MARKER_WIDTH

    override fun drawLeadingMargin(
        canvas: Canvas,
        paint: Paint,
        x: Int,
        dir: Int,
        top: Int,
        baseline: Int,
        bottom: Int,
        text: CharSequence,
        start: Int,
        end: Int,
        first: Boolean,
        layout: Layout?
    ) {
        if (!first) return
        canvas.drawText("$number.", (x + dir * MARKER_WIDTH).toFloat(), baseline.toFloat(), paint)
    }

    private companion object {
        const val MARKER_WIDTH = 40
    }
}

internal class TaskListItemSpan(
    private val checked: Boolean,
    private val gapWidth: Int
) : LeadingMarginSpan {

    override fun getLeadingMargin(first: Boolean): Int = gapWidth + MARKER_WIDTH

    override fun drawLeadingMargin(
        canvas: Canvas,
        paint: Paint,
        x: Int,
        dir: Int,
        top: Int,
        baseline: Int,
        bottom: Int,
        text: CharSequence,
        start: Int,
        end: Int,
        first: Boolean,
        layout: Layout?
    ) {
        if (!first) return
        val glyph = if (checked) "☑" else "☐"
        canvas.drawText(glyph, (x + dir * MARKER_WIDTH).toFloat(), baseline.toFloat(), paint)
    }

    private companion object {
        const val MARKER_WIDTH = 40
    }
}
