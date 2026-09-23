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

// Shared by CodeBlockBackgroundSpan and ThemedQuoteSpan: draws a full rounded-rect
// background across a (possibly multi-line) block, only rounding the very top corners
// (first line) and very bottom corners (last line) - drawn as a full round-rect then
// squared off on the far side, which is cheaper than tracking per-glyph paths.
private fun drawRoundedLineBackground(
    canvas: Canvas,
    paint: Paint,
    left: Int,
    right: Int,
    top: Int,
    bottom: Int,
    color: Int,
    cornerRadiusPx: Float,
    isFirstLine: Boolean,
    isLastLine: Boolean
) {
    val rect = RectF(left.toFloat(), top.toFloat(), right.toFloat(), bottom.toFloat())
    val originalColor = paint.color
    paint.color = color
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

// Also implements LineHeightSpan to grow the first line's ascent by `topPaddingPx` and the
// last line's descent by `bottomPaddingPx`: Android's Spannable/Layout has no notion of
// "block padding" the way CSS does, so without this the code text touches the background's
// top and bottom edges directly. Growing the line metrics reserves real layout space
// (Layout passes the already-grown top/bottom into drawBackground above), rather than just
// drawing a taller rect that would bleed into the surrounding paragraph's own lines.
// `topPaddingPx` is intentionally taller than `bottomPaddingPx`: every code block gets a
// copy-button overlay in its top-right corner (see THKMDView.TextSegmentFrame), and the
// button needs somewhere to sit that isn't directly on top of the first line's actual text.
internal class CodeBlockBackgroundSpan(
    val backgroundColor: Int,
    val cornerRadiusPx: Float,
    private val topPaddingPx: Int,
    private val bottomPaddingPx: Int,
    private val spanStart: Int,
    private val spanEnd: Int,
    val copyButtonGutterPx: Int = 0,
    val containerBackground: Boolean = false
) : LineBackgroundSpan, LineHeightSpan {
    var drawsInHost: Boolean = false

    override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, v: Int, fm: Paint.FontMetricsInt) {
        val isFirstLine = start <= spanStart
        val isLastLine = end >= spanEnd
        if (isFirstLine) {
            fm.ascent -= topPaddingPx
            fm.top -= topPaddingPx
        }
        if (isLastLine) {
            fm.descent += bottomPaddingPx
            fm.bottom += bottomPaddingPx
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
        if (containerBackground || drawsInHost) return // The host paints beyond TextView's clip.
        val indent = (text as? android.text.Spanned)
            ?.getSpans(start, end, LeadingMarginSpan::class.java)
            ?.filterNot { it is CodeBlockPaddingSpan }
            ?.sumOf { it.getLeadingMargin(true) } ?: 0
        drawRoundedLineBackground(
            canvas, paint, left + indent, right, top, bottom, backgroundColor, cornerRadiusPx,
            isFirstLine = start <= spanStart, isLastLine = end >= spanEnd
        )
    }
}

// Adds left inset inside a code block's rounded background without drawing anything.
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
//
// Only the OUTERMOST quote in a nested `> > quote` gets the rounded background fill (a
// non-null `backgroundColor`, set by MarkdownSpanVisitor only when blockQuoteDepth == 0
// at the point this span's range starts): an inner span's own start/end only cover the
// nested portion, so if it also drew a rounded background, the "first/last line" corner
// rounding would trigger at the nested quote's boundary - a visual notch in the middle
// of what should be one continuous rounded block. Nested levels still get their own bar.
internal class ThemedQuoteSpan(
    private val barColor: Int,
    val backgroundColor: Int? = null,
    val cornerRadiusPx: Float = 0f,
    private val topPaddingPx: Int = 0,
    private val bottomPaddingPx: Int = 0,
    private val spanStart: Int = 0,
    private val spanEnd: Int = 0,
    private val stripeWidthPx: Int = 6,
    private val gapWidthPx: Int = 20,
    private val leftInsetPx: Int = 0,
    private val barVerticalInsetPx: Int = 0,
    val copyButtonGutterPx: Int = 0,
    val containerBackground: Boolean = false,
    private val nestedTopPaddingPx: Int = 0,
    private val nestedBottomPaddingPx: Int = 0
) : LeadingMarginSpan, LineBackgroundSpan, LineHeightSpan {
    var drawsInHost: Boolean = false

    private var expandedAscent: Int? = null
    private var expandedTop: Int? = null
    private var expandedDescent: Int? = null
    private var expandedBottom: Int? = null

    // Standalone quotes reserve padding on their TextView; embedded quotes retain
    // per-block padding here. Nested spans never add another layer of line padding.
    override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, v: Int, fm: Paint.FontMetricsInt) {
        if (nestedTopPaddingPx > 0) {
            // StaticLayout may reuse the previous wrapped line's font metrics.
            // Remove our previous addition before applying it to the first line only.
            if (fm.ascent == expandedAscent) fm.ascent += nestedTopPaddingPx
            if (fm.top == expandedTop) fm.top += nestedTopPaddingPx
            expandedAscent = null
            expandedTop = null
            if (start <= spanStart) {
                fm.ascent -= nestedTopPaddingPx
                fm.top -= nestedTopPaddingPx
                expandedAscent = fm.ascent
                expandedTop = fm.top
            }
        }
        if (nestedBottomPaddingPx > 0) {
            if (fm.descent == expandedDescent) fm.descent -= nestedBottomPaddingPx
            if (fm.bottom == expandedBottom) fm.bottom -= nestedBottomPaddingPx
            expandedDescent = null
            expandedBottom = null
            if (end >= spanEnd) {
                fm.descent += nestedBottomPaddingPx
                fm.bottom += nestedBottomPaddingPx
                expandedDescent = fm.descent
                expandedBottom = fm.bottom
            }
        }
        if (backgroundColor == null) return
        if (start <= spanStart) {
            fm.ascent -= topPaddingPx
            fm.top -= topPaddingPx
        }
        if (end >= spanEnd) {
            fm.descent += bottomPaddingPx
            fm.bottom += bottomPaddingPx
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
        if (backgroundColor == null || containerBackground || drawsInHost) return
        drawRoundedLineBackground(
            canvas, paint, left, right, top, bottom, backgroundColor, cornerRadiusPx,
            isFirstLine = start <= spanStart, isLastLine = end >= spanEnd
        )
    }

    override fun getLeadingMargin(first: Boolean): Int = leftInsetPx + stripeWidthPx + gapWidthPx

    internal fun barBottomForLine(baseline: Int, bottom: Int, fontDescent: Int, isLastLine: Boolean): Int {
        if (!isLastLine) return bottom
        // All nested quotes on this line share its expanded descent, including
        // padding contributed by an ancestor. Subtracting only our own padding
        // gives level 2 and level 3 different ends. Use the unexpanded font's
        // baseline-relative bottom for every nested bar instead.
        return if (backgroundColor == null) baseline + fontDescent
        else bottom - barVerticalInsetPx
    }

    // Drawn as a rounded "pill" (only its very top and very bottom corners rounded, same
    // flat-in-the-middle technique as drawRoundedLineBackground, so a multi-line bar reads
    // as one continuous shape) inset a little from the block's left/top/bottom edges,
    // rather than a sharp rectangle flush against them.
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
        val barLeft = (x + dir * leftInsetPx).toFloat()
        val barRight = barLeft + dir * stripeWidthPx
        val isFirstLine = start <= spanStart
        val isLastLine = end >= spanEnd
        var barTop = top
        val barBottom = barBottomForLine(baseline, bottom, paint.fontMetricsInt.descent, isLastLine)
        if (isFirstLine) barTop += barVerticalInsetPx + nestedTopPaddingPx
        drawRoundedLineBackground(
            canvas, paint,
            left = minOf(barLeft, barRight).toInt(), right = maxOf(barLeft, barRight).toInt(),
            top = barTop, bottom = barBottom,
            color = barColor, cornerRadiusPx = stripeWidthPx / 2f,
            isFirstLine = isFirstLine, isLastLine = isLastLine
        )
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
        if (!first || (text as? android.text.Spanned)?.getSpanStart(this) != start) return
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
        if (!first || (text as? android.text.Spanned)?.getSpanStart(this) != start) return
        // Shared outline/check geometry with iOS; no platform-font checkbox glyphs.
        val iconPaint = Paint(paint).apply {
            style = Paint.Style.STROKE
            strokeWidth = markerWidthPx / 10f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val side = markerWidthPx.toFloat()
        val left = if (dir > 0) x.toFloat() else x - side
        val topEdge = baseline + (paint.fontMetrics.ascent + paint.fontMetrics.descent - side) / 2
        val inset = iconPaint.strokeWidth / 2
        canvas.drawRoundRect(RectF(left + inset, topEdge + inset, left + side - inset, topEdge + side - inset), side / 8, side / 8, iconPaint)
        if (checked) {
            val path = android.graphics.Path().apply {
                moveTo(left + side * 0.22f, topEdge + side * 0.51f)
                lineTo(left + side * 0.43f, topEdge + side * 0.72f)
                lineTo(left + side * 0.79f, topEdge + side * 0.28f)
            }
            canvas.drawPath(path, iconPaint)
        }
    }
}

// Adds a little extra leading between the lines *inside* a multi-line block quote (on
// top of, not instead of, ThemedQuoteSpan's own first/last-line block padding) so a
// wrapped or multi-paragraph quote doesn't read as visually cramped.
internal class QuoteInteriorLineSpacingSpan(
    private val extraSpacingPx: Int,
    private val spanStart: Int,
    private val spanEnd: Int
) : LineHeightSpan {
    override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, v: Int, fm: Paint.FontMetricsInt) {
        if (start < spanStart || end > spanEnd) return
        fm.descent += extraSpacingPx
        fm.bottom += extraSpacingPx
    }
}

// Draws a real solid divider line (rather than relying on a run of Unicode box-drawing
// characters, whose glyph tiling/side-bearing varies by font and previously rendered
// visibly dashed on iOS while looking solid on Android with a different font) - this way
// both platforms render an identical, font-independent line regardless of typeface.
internal class ThematicBreakSpan(
    private val color: Int,
    private val thicknessPx: Float
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
        val centerY = (top + bottom) / 2f
        val originalColor = paint.color
        paint.color = color
        canvas.drawRect(left.toFloat(), centerY - thicknessPx / 2f, right.toFloat(), centerY + thicknessPx / 2f, paint)
        paint.color = originalColor
    }
}
