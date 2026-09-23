package com.thk.mdview

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.TextView
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Real GFM table rendering: a per-column-width grid that scrolls horizontally
 * independently of the surrounding message text when it's wider than the available
 * width. Cell content is pre-rendered inline-Markdown [CharSequence]s (see
 * [InlineSpanBuilder]/[MarkdownSpanVisitor]), so bold/italic/code/links/strikethrough
 * work inside cells exactly like in normal text flow.
 */
class THKTableView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : HorizontalScrollView(context, attrs) {

    private val grid = TableGrid(context)

    init {
        isHorizontalScrollBarEnabled = true
        addView(grid, ViewGroup.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    /**
     * [data]'s cell content is already fully rendered (including [android.text.style.ClickableSpan]s
     * for any links/images inside a cell, wired up at render time - see
     * [MarkdownSpanVisitor.buildTableData]), so this view only needs [android.text.method.LinkMovementMethod]
     * on each cell to make those spans tappable; it takes no separate click callback.
     */
    fun setData(data: THKTableData, theme: THKMDTheme) {
        grid.bind(data, theme)
    }

    /** Exposed for tests: the laid-out cell views, row-major, header first. */
    internal fun cellViewAt(row: Int, col: Int): TextView? = grid.cellAt(row, col)

    private class TableGrid(context: Context) : ViewGroup(context) {

        private val density = context.resources.displayMetrics.density
        // Keep Android borders visible at high density: 1dp, snapped to whole pixels.
        private val borderPx = density.roundToInt().coerceAtLeast(1)
        private val minColumnWidthPx = (48 * density).toInt()
        private val maxColumnWidthPx = (260 * density).toInt()
        private val minRowHeightPx = (36 * density).toInt()
        private val cellPaddingHPx = (10 * density).toInt()
        private val cellPaddingVPx = (8 * density).toInt()

        private val borderPaint = Paint().apply { style = Paint.Style.FILL }

        init {
            // ViewGroups skip onDraw() by default (the "willNotDraw" optimization, since
            // most ViewGroups only draw children) - without this, the border lines below
            // were never actually being drawn at all, not just low-contrast.
            setWillNotDraw(false)
        }

        private var columnCount = 0
        private var rowCount = 0
        private var cells: Array<Array<TextView?>> = arrayOf()
        private var colWidths = IntArray(0)
        private var rowHeights = IntArray(0)
        private var xBoundaries = IntArray(0)
        private var yBoundaries = IntArray(0)

        fun cellAt(row: Int, col: Int): TextView? = cells.getOrNull(row)?.getOrNull(col)

        fun bind(data: THKTableData, theme: THKMDTheme) {
            removeAllViews()
            borderPaint.color = theme.tableBorderColor

            columnCount = maxOf(data.headerRow.size, data.bodyRows.maxOfOrNull { it.size } ?: 0)
            rowCount = (if (data.headerRow.isNotEmpty()) 1 else 0) + data.bodyRows.size
            if (columnCount == 0 || rowCount == 0) {
                cells = arrayOf()
                requestLayout()
                invalidate()
                return
            }

            val alignments = List(columnCount) { i -> data.columnAlignments.getOrNull(i) ?: THKTableAlignment.START }
            val rows = mutableListOf<List<CharSequence>>()
            if (data.headerRow.isNotEmpty()) rows.add(data.headerRow)
            rows.addAll(data.bodyRows)

            cells = Array(rowCount) { rowIndex ->
                val isHeader = rowIndex == 0 && data.headerRow.isNotEmpty()
                val rowContent = rows[rowIndex]
                Array(columnCount) { colIndex ->
                    val content = rowContent.getOrNull(colIndex) ?: ""
                    createCell(content, isHeader, alignments[colIndex], theme).also { addView(it) }
                }
            }
        }

        private fun createCell(
            content: CharSequence,
            isHeader: Boolean,
            alignment: THKTableAlignment,
            theme: THKMDTheme
        ): TextView = TextView(context).apply {
            text = content
            movementMethod = android.text.method.LinkMovementMethod.getInstance()
            setPadding(cellPaddingHPx, cellPaddingVPx, cellPaddingHPx, cellPaddingVPx)
            setTextColor(if (isHeader) theme.headingTextColor else theme.bodyTextColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, theme.bodyFontSizeSp)
            typeface = if (isHeader) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            gravity = Gravity.CENTER_VERTICAL or when (alignment) {
                THKTableAlignment.START -> Gravity.START
                THKTableAlignment.CENTER -> Gravity.CENTER_HORIZONTAL
                THKTableAlignment.END -> Gravity.END
            }
            if (isHeader) setBackgroundColor(theme.tableHeaderBackgroundColor)
            minimumWidth = minColumnWidthPx
            minimumHeight = minRowHeightPx
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            if (columnCount == 0 || rowCount == 0) {
                setMeasuredDimension(0, 0)
                return
            }
            val widths = IntArray(columnCount)
            val heights = IntArray(rowCount)

            for (row in 0 until rowCount) {
                for (col in 0 until columnCount) {
                    val cell = cellAt(row, col) ?: continue
                    cell.measure(
                        MeasureSpec.makeMeasureSpec(maxColumnWidthPx, MeasureSpec.AT_MOST),
                        MeasureSpec.UNSPECIFIED
                    )
                    widths[col] = maxOf(widths[col], min(cell.measuredWidth, maxColumnWidthPx))
                }
            }
            for (col in 0 until columnCount) widths[col] = maxOf(widths[col], minColumnWidthPx)

            for (row in 0 until rowCount) {
                for (col in 0 until columnCount) {
                    val cell = cellAt(row, col) ?: continue
                    cell.measure(
                        MeasureSpec.makeMeasureSpec(widths[col], MeasureSpec.EXACTLY),
                        MeasureSpec.UNSPECIFIED
                    )
                    heights[row] = maxOf(heights[row], cell.measuredHeight)
                }
                heights[row] = maxOf(heights[row], minRowHeightPx)
            }

            colWidths = widths
            rowHeights = heights
            xBoundaries = boundariesOf(widths)
            yBoundaries = boundariesOf(heights)

            val totalWidth = widths.sum() + borderPx * (columnCount + 1)
            val totalHeight = heights.sum() + borderPx * (rowCount + 1)
            setMeasuredDimension(totalWidth, totalHeight)
        }

        private fun boundariesOf(sizes: IntArray): IntArray {
            val boundaries = IntArray(sizes.size + 1)
            var pos = borderPx
            boundaries[0] = pos
            for (i in sizes.indices) {
                pos += sizes[i] + borderPx
                boundaries[i + 1] = pos
            }
            return boundaries
        }

        override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
            if (columnCount == 0 || rowCount == 0) return
            for (row in 0 until rowCount) {
                val top = yBoundaries[row]
                val bottom = top + rowHeights[row]
                for (col in 0 until columnCount) {
                    val left = xBoundaries[col]
                    val right = left + colWidths[col]
                    cellAt(row, col)?.layout(left, top, right, bottom)
                }
            }
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (columnCount == 0 || rowCount == 0) return
            val totalWidth = xBoundaries.last().toFloat()
            val totalHeight = yBoundaries.last().toFloat()
            for (y in yBoundaries) {
                canvas.drawRect(0f, (y - borderPx).toFloat(), totalWidth, y.toFloat(), borderPaint)
            }
            for (x in xBoundaries) {
                canvas.drawRect((x - borderPx).toFloat(), 0f, x.toFloat(), totalHeight, borderPaint)
            }
        }
    }
}
