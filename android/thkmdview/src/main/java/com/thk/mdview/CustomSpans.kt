package com.thk.mdview

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.Layout
import android.text.style.ClickableSpan
import android.text.style.LeadingMarginSpan
import android.text.style.LineBackgroundSpan
import android.text.style.LineHeightSpan
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
//
// Also implements LineHeightSpan to grow the first line's ascent and the last line's
// descent by `verticalPaddingPx`: Android's Spannable/Layout has no notion of "block
// padding" the way CSS does, so without this the code text touches the background's top
// and bottom edges directly. Growing the line metrics reserves real layout space (Layout
// passes the already-grown top/bottom into drawBackground above), rather than just
// drawing a taller rect that would bleed into the surrounding paragraph's own lines.
internal class CodeBlockBackgroundSpan(
    private val backgroundColor: Int,
    private val cornerRadiusPx: Float,
    private val verticalPaddingPx: Int,
    private val spanStart: Int,
    private val spanEnd: Int
) : LineBackgroundSpan, LineHeightSpan {

    override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, v: Int, fm: Paint.FontMetricsInt) {
        val isFirstLine = start <= spanStart
        val isLastLine = end >= spanEnd
        if (isFirstLine) {
            fm.ascent -= verticalPaddingPx
            fm.top -= verticalPaddingPx
        }
        if (isLastLine) {
            fm.descent += verticalPaddingPx
            fm.bottom += verticalPaddingPx
        }
    }

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

// markerWidthPx must be measured (Paint.measureText) against the marker text this span
// actually draws, at the theme's real body text size - a fixed guess here previously
// caused the marker glyph to overlap the item text on higher-density screens, since the
// glyph was drawn at an offset near the *end* of a too-small, unscaled pixel margin.
internal class OrderedListItemSpan(
    private val number: Int,
    private val markerWidthPx: Int,
    private val gapWidth: Int
) : LeadingMarginSpan {

    override fun getLeadingMargin(first: Boolean): Int = markerWidthPx + gapWidth

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
        canvas.drawText("$number.", x.toFloat(), baseline.toFloat(), paint)
    }
}

internal class TaskListItemSpan(
    private val checked: Boolean,
    private val markerWidthPx: Int,
    private val gapWidth: Int
) : LeadingMarginSpan {

    override fun getLeadingMargin(first: Boolean): Int = markerWidthPx + gapWidth

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
        canvas.drawText(glyph, x.toFloat(), baseline.toFloat(), paint)
    }
}
