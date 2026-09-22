package com.thk.mdview

import android.graphics.Canvas
import android.graphics.Paint
import android.text.Layout
import android.text.style.ClickableSpan
import android.text.style.LeadingMarginSpan
import android.text.style.LineBackgroundSpan
import android.view.View

internal class LinkClickableSpan(
    private val url: String,
    private val linkHandler: (String) -> Boolean
) : ClickableSpan() {
    override fun onClick(widget: View) {
        linkHandler(url)
    }
}

// TODO(v1): code blocks currently wrap like normal text; render them with
// independent horizontal scroll instead once the composite-view escape hatch exists.
internal class CodeBlockBackgroundSpan(private val color: Int) : LineBackgroundSpan {
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
        val originalColor = paint.color
        paint.color = color
        canvas.drawRect(left.toFloat(), top.toFloat(), right.toFloat(), bottom.toFloat(), paint)
        paint.color = originalColor
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
