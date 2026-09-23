package com.thk.mdview

import android.content.Context
import android.view.Gravity
import android.view.View
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.roundToInt

@RunWith(AndroidJUnit4::class)
class THKTableViewTest {
    @Test
    @org.robolectric.annotation.GraphicsMode(org.robolectric.annotation.GraphicsMode.Mode.NATIVE)
    @org.robolectric.annotation.Config(qualifiers = "xxhdpi")
    fun outerBordersOccupyOneDpWithoutClipping() {
        val table = measuredTable(THKTableData(listOf(THKTableAlignment.START), listOf("H"), listOf(listOf("body"))))
        val grid = table.getChildAt(0)
        val bitmap = android.graphics.Bitmap.createBitmap(grid.width, grid.height, android.graphics.Bitmap.Config.ARGB_8888)
        grid.draw(android.graphics.Canvas(bitmap))
        val body = table.cellViewAt(1, 0)!!
        val y = body.top + body.height / 2
        val border = context.resources.displayMetrics.density.roundToInt().coerceAtLeast(1)
        assertThat(border).isGreaterThan(1)
        for (offset in 0 until border) {
            assertThat(bitmap.getPixel(offset, y)).isEqualTo(theme.tableBorderColor)
            assertThat(bitmap.getPixel(grid.width - 1 - offset, y)).isEqualTo(theme.tableBorderColor)
        }
        assertThat(bitmap.getPixel(border, y)).isNotEqualTo(theme.tableBorderColor)
        assertThat(bitmap.getPixel(grid.width - 1 - border, y)).isNotEqualTo(theme.tableBorderColor)
    }

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val theme = THKMDTheme.Default

    private fun measuredTable(data: THKTableData): THKTableView {
        val view = THKTableView(context)
        view.setData(data, theme)
        view.measure(
            View.MeasureSpec.makeMeasureSpec(2000, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(2000, View.MeasureSpec.AT_MOST)
        )
        view.layout(0, 0, view.measuredWidth, view.measuredHeight)
        return view
    }

    @Test
    @org.robolectric.annotation.GraphicsMode(org.robolectric.annotation.GraphicsMode.Mode.NATIVE)
    fun columnLimitsAndBordersUseSharedLogicalWidths() {
        val table = measuredTable(THKTableData(listOf(THKTableAlignment.START, THKTableAlignment.START),
            listOf("", ""), listOf(listOf("", "x".repeat(200)))))
        val density = context.resources.displayMetrics.density
        val first = table.cellViewAt(0, 0)!!
        val second = table.cellViewAt(0, 1)!!
        assertThat(first.width).isEqualTo((48 * density).toInt())
        assertThat(second.width).isEqualTo((240 * density).toInt())
        assertThat(first.left).isEqualTo(0)
        assertThat(second.left).isEqualTo(first.right)
        assertThat(table.getChildAt(0).width).isEqualTo(first.width + second.width)
    }

    @Test
    fun columnAlignment_mapsToTextViewGravityPerColumn() {
        val data = THKTableData(
            columnAlignments = listOf(THKTableAlignment.START, THKTableAlignment.CENTER, THKTableAlignment.END),
            headerRow = listOf("L", "C", "R"),
            bodyRows = listOf(listOf("a", "b", "c"))
        )
        val view = measuredTable(data)

        assertThat(view.cellViewAt(1, 0)!!.gravity).isEqualTo(Gravity.CENTER_VERTICAL or Gravity.START)
        assertThat(view.cellViewAt(1, 1)!!.gravity).isEqualTo(Gravity.CENTER_VERTICAL or Gravity.CENTER_HORIZONTAL)
        assertThat(view.cellViewAt(1, 2)!!.gravity).isEqualTo(Gravity.CENTER_VERTICAL or Gravity.END)
    }

    @Test
    fun missingColumnAlignment_defaultsToStart() {
        val data = THKTableData(
            columnAlignments = emptyList(),
            headerRow = listOf("H"),
            bodyRows = listOf(listOf("v"))
        )
        val view = measuredTable(data)
        assertThat(view.cellViewAt(1, 0)!!.gravity).isEqualTo(Gravity.CENTER_VERTICAL or Gravity.START)
    }

    @Test
    fun headerRow_isBoldAndBodyRowIsNot() {
        val data = THKTableData(
            columnAlignments = listOf(THKTableAlignment.START),
            headerRow = listOf("Head"),
            bodyRows = listOf(listOf("body"))
        )
        val view = measuredTable(data)

        val header = view.cellViewAt(0, 0)!!
        val body = view.cellViewAt(1, 0)!!

        // Robolectric's legacy graphics shadow doesn't reliably surface Typeface.isBold()
        // for the DEFAULT_BOLD constant, so this asserts the exact Typeface THKTableView
        // assigns rather than relying on that derived property.
        assertThat(header.typeface).isSameInstanceAs(android.graphics.Typeface.DEFAULT_BOLD)
        assertThat(body.typeface).isSameInstanceAs(android.graphics.Typeface.DEFAULT)
    }

    @Test
    fun aVeryLongSingleCell_isCappedRatherThanBlowingOutTheTable() {
        val data = THKTableData(
            columnAlignments = listOf(THKTableAlignment.START),
            headerRow = listOf("H"),
            bodyRows = listOf(listOf("x".repeat(2000)))
        )
        val view = measuredTable(data)

        val density = context.resources.displayMetrics.density
        assertThat(view.measuredWidth).isLessThan((320 * density).toInt())
    }

    @Test
    fun rowsAndColumnsMatchTheSuppliedData() {
        val data = THKTableData(
            columnAlignments = listOf(THKTableAlignment.START, THKTableAlignment.START),
            headerRow = listOf("A", "B"),
            bodyRows = listOf(listOf("1", "2"), listOf("3", "4"))
        )
        val view = measuredTable(data)

        assertThat(view.cellViewAt(0, 0)?.text.toString()).isEqualTo("A")
        assertThat(view.cellViewAt(0, 1)?.text.toString()).isEqualTo("B")
        assertThat(view.cellViewAt(1, 0)?.text.toString()).isEqualTo("1")
        assertThat(view.cellViewAt(2, 1)?.text.toString()).isEqualTo("4")
        assertThat(view.cellViewAt(3, 0)).isNull()
    }
}
