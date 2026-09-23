package com.thk.mdview.sample

import android.app.Dialog
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.fragment.app.FragmentManager
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.slider.Slider
import com.thk.mdview.THKMDTheme
import kotlin.math.roundToInt

private enum class ColorProperty(val labelResId: Int) {
    ALERT_NOTE(R.string.theme_alert_note),
    ALERT_TIP(R.string.theme_alert_tip),
    ALERT_IMPORTANT(R.string.theme_alert_important),
    ALERT_WARNING(R.string.theme_alert_warning),
    ALERT_CAUTION(R.string.theme_alert_caution),
    BODY_TEXT(R.string.theme_prop_body_text),
    HEADING_TEXT(R.string.theme_prop_heading_text),
    LINK(R.string.theme_prop_link),
    CODE_TEXT(R.string.theme_prop_code_text),
    CODE_BACKGROUND(R.string.theme_prop_code_background),
    BLOCK_QUOTE_BAR(R.string.theme_prop_quote_bar),
    BLOCK_QUOTE_TEXT(R.string.theme_prop_quote_text),
    BLOCK_QUOTE_BACKGROUND(R.string.theme_prop_quote_background),
    TABLE_BORDER(R.string.theme_prop_table_border),
    TABLE_HEADER_BACKGROUND(R.string.theme_prop_table_header_background),
    VIEW_BACKGROUND(R.string.theme_prop_view_background)
}

private enum class SizeProperty(val labelResId: Int, val valueFrom: Float, val valueTo: Float, val unit: String) {
    LIST_BULLET_SCALE(R.string.theme_list_bullet_scale, 0.1f, 0.4f, "×"),
    FOOTNOTE_SCALE(R.string.theme_footnote_scale, 0.5f, 1f, "×"),
    MATH_SCALE(R.string.theme_math_scale, 0.5f, 2f, "×"),
    CODE_CORNER_RADIUS(R.string.theme_prop_code_corner_radius, 0f, 20f, "dp"),
    BODY_FONT_SIZE(R.string.theme_prop_body_font_size, 10f, 24f, "sp"),
    CODE_FONT_SIZE(R.string.theme_prop_code_font_size, 10f, 24f, "sp")
}

// ~16 curated presets (four neutrals, plus a light+saturated variant of six hues) rather
// than a full HSV/RGB picker widget: there's no built-in Android color picker, and this
// project deliberately avoids new third-party dependencies (see DefaultTHKImageLoader's
// hand-rolled caching instead of pulling in Coil) - a tap-to-pick grid is simpler and
// sufficient for a sample-app settings sheet.
private val COLOR_SWATCH_PRESETS: List<Int> = listOf(
    0xFF1C1C1E.toInt(), 0xFF48484A.toInt(), 0xFFC7C7CC.toInt(), 0xFFFFFFFF.toInt(),
    0xFFFF3B30.toInt(), 0xFFFFD1CC.toInt(),
    0xFFFF9500.toInt(), 0xFFFFE0B2.toInt(),
    0xFFFFCC00.toInt(), 0xFFFFF3B0.toInt(),
    0xFF34C759.toInt(), 0xFFC8F7D4.toInt(),
    0xFF0A84FF.toInt(), 0xFFCCE7FF.toInt(),
    0xFFAF52DE.toInt(), 0xFFEBD6F7.toInt()
)

private fun swatchDrawable(context: Context, color: Int): GradientDrawable {
    val density = context.resources.displayMetrics.density
    return GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
        setStroke((1 * density).toInt().coerceAtLeast(1), 0x33000000)
    }
}

/**
 * Live-editable settings sheet for every [THKMDTheme] property. Every control's change
 * listener rebuilds a whole [THKMDTheme] from the current value of *all* controls (not
 * just the one that changed) and hands it to [onThemeChanged] - the caller wires that
 * straight to [ChatAdapter.setTheme], the same mechanism the old toolbar toggle used, so
 * there's exactly one code path that pushes a theme onto bound bubbles.
 */
class ThemeSettingsSheet : BottomSheetDialogFragment() {

    private var initialTheme: THKMDTheme = THKMDTheme.Default
    private var onThemeChanged: (THKMDTheme) -> Unit = {}

    private val colorValues = mutableMapOf<ColorProperty, Int>()
    private val sizeValues = mutableMapOf<SizeProperty, Float>()
    private val swatchViews = mutableMapOf<ColorProperty, View>()
    private val sliderViews = mutableMapOf<SizeProperty, Pair<TextView, Slider>>()

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = super.onCreateDialog(savedInstanceState) as BottomSheetDialog
        // Opens half-expanded, not full screen, so the chat behind the sheet stays
        // visible while dragging a slider or picking a color - that live view of the
        // effect is the whole point of live-apply, not just an instantaneous callback.
        dialog.setOnShowListener {
            val sheetView = dialog.findViewById<FrameLayout>(com.google.android.material.R.id.design_bottom_sheet)
            if (sheetView != null) {
                val behavior = BottomSheetBehavior.from(sheetView)
                behavior.isFitToContents = false
                behavior.halfExpandedRatio = 0.6f
                behavior.state = BottomSheetBehavior.STATE_HALF_EXPANDED
            }
        }
        return dialog
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        loadValues(initialTheme)
        val root = inflater.inflate(R.layout.sheet_theme_settings, container, false)

        root.findViewById<View>(R.id.presetDefaultButton).setOnClickListener { applyPreset(THKMDTheme.Default) }
        root.findViewById<View>(R.id.presetVibrantButton).setOnClickListener { applyPreset(ALT_THEME) }

        val colorContainer = root.findViewById<LinearLayout>(R.id.colorRowContainer)
        ColorProperty.values().forEach { prop -> colorContainer.addView(buildColorRow(inflater, colorContainer, prop)) }

        val sizeContainer = root.findViewById<LinearLayout>(R.id.sizeRowContainer)
        SizeProperty.values().forEach { prop -> sizeContainer.addView(buildSizeRow(inflater, sizeContainer, prop)) }

        return root
    }

    private fun loadValues(theme: THKMDTheme) {
        sizeValues[SizeProperty.LIST_BULLET_SCALE] = theme.listBulletScale
        sizeValues[SizeProperty.FOOTNOTE_SCALE] = theme.footnoteScale
        sizeValues[SizeProperty.MATH_SCALE] = theme.mathScale
        colorValues[ColorProperty.ALERT_NOTE] = theme.alertNoteColor
        colorValues[ColorProperty.ALERT_TIP] = theme.alertTipColor
        colorValues[ColorProperty.ALERT_IMPORTANT] = theme.alertImportantColor
        colorValues[ColorProperty.ALERT_WARNING] = theme.alertWarningColor
        colorValues[ColorProperty.ALERT_CAUTION] = theme.alertCautionColor
        colorValues[ColorProperty.BODY_TEXT] = theme.bodyTextColor
        colorValues[ColorProperty.HEADING_TEXT] = theme.headingTextColor
        colorValues[ColorProperty.LINK] = theme.linkColor
        colorValues[ColorProperty.CODE_TEXT] = theme.codeTextColor
        colorValues[ColorProperty.CODE_BACKGROUND] = theme.codeBackgroundColor
        colorValues[ColorProperty.BLOCK_QUOTE_BAR] = theme.blockQuoteBarColor
        colorValues[ColorProperty.BLOCK_QUOTE_TEXT] = theme.blockQuoteTextColor
        colorValues[ColorProperty.BLOCK_QUOTE_BACKGROUND] = theme.blockQuoteBackgroundColor
        colorValues[ColorProperty.TABLE_BORDER] = theme.tableBorderColor
        colorValues[ColorProperty.TABLE_HEADER_BACKGROUND] = theme.tableHeaderBackgroundColor
        colorValues[ColorProperty.VIEW_BACKGROUND] = theme.backgroundColor
        sizeValues[SizeProperty.CODE_CORNER_RADIUS] = theme.codeBlockCornerRadiusDp
        sizeValues[SizeProperty.BODY_FONT_SIZE] = theme.bodyFontSizeSp
        sizeValues[SizeProperty.CODE_FONT_SIZE] = theme.codeFontSizeSp
    }

    private fun applyPreset(theme: THKMDTheme) {
        initialTheme = theme
        loadValues(theme)
        colorValues.forEach { (prop, color) -> swatchViews[prop]?.background = swatchDrawable(requireContext(), color) }
        sizeValues.forEach { (prop, value) ->
            val (label, slider) = sliderViews.getValue(prop)
            slider.value = value.coerceIn(prop.valueFrom, prop.valueTo)
            label.text = sizeLabelText(prop, value)
        }
        pushTheme()
    }

    private fun buildColorRow(inflater: LayoutInflater, parent: ViewGroup, prop: ColorProperty): View {
        val row = inflater.inflate(R.layout.row_theme_color, parent, false)
        val swatch = row.findViewById<View>(R.id.swatchView)
        val label = row.findViewById<TextView>(R.id.labelText)
        label.text = getString(prop.labelResId)
        swatch.background = swatchDrawable(requireContext(), colorValues.getValue(prop))
        swatch.contentDescription = getString(prop.labelResId)
        swatch.setOnClickListener { showColorPicker(prop) }
        row.setOnClickListener { showColorPicker(prop) }
        swatchViews[prop] = swatch
        return row
    }

    private fun buildSizeRow(inflater: LayoutInflater, parent: ViewGroup, prop: SizeProperty): View {
        val row = inflater.inflate(R.layout.row_theme_slider, parent, false)
        val label = row.findViewById<TextView>(R.id.labelText)
        val slider = row.findViewById<Slider>(R.id.slider)
        slider.valueFrom = prop.valueFrom
        slider.valueTo = prop.valueTo
        slider.stepSize = if (prop.unit == "×") 0f else 1f
        val current = sizeValues.getValue(prop)
        slider.value = current.coerceIn(prop.valueFrom, prop.valueTo)
        label.text = sizeLabelText(prop, current)
        slider.addOnChangeListener { _, value, fromUser ->
            sizeValues[prop] = value
            label.text = sizeLabelText(prop, value)
            if (fromUser) pushTheme()
        }
        sliderViews[prop] = label to slider
        return row
    }

    private fun sizeLabelText(prop: SizeProperty, value: Float): String =
        "${getString(prop.labelResId)}: ${if (prop.unit == "×") String.format(java.util.Locale.ROOT, "%.2f", value) else value.roundToInt().toString()}${prop.unit}"

    private fun showColorPicker(prop: ColorProperty) {
        val context = requireContext()
        var dialog: Dialog? = null
        val grid = buildColorGrid(context) { color ->
            colorValues[prop] = color
            swatchViews[prop]?.background = swatchDrawable(context, color)
            pushTheme()
            dialog?.dismiss()
        }
        dialog = MaterialAlertDialogBuilder(context)
            .setTitle(getString(prop.labelResId))
            .setView(grid)
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun buildColorGrid(context: Context, onPick: (Int) -> Unit): GridLayout {
        val density = context.resources.displayMetrics.density
        val grid = GridLayout(context).apply {
            columnCount = 4
            val paddingPx = (8 * density).toInt()
            setPadding(paddingPx, paddingPx, paddingPx, paddingPx)
        }
        val swatchSizePx = (48 * density).toInt()
        val marginPx = (6 * density).toInt()
        COLOR_SWATCH_PRESETS.forEach { color ->
            val swatch = View(context).apply {
                background = swatchDrawable(context, color)
                setOnClickListener { onPick(color) }
            }
            val params = GridLayout.LayoutParams().apply {
                width = swatchSizePx
                height = swatchSizePx
                setMargins(marginPx, marginPx, marginPx, marginPx)
            }
            grid.addView(swatch, params)
        }
        return grid
    }

    private fun pushTheme() {
        onThemeChanged(buildTheme())
    }

    private fun buildTheme(): THKMDTheme = initialTheme.copy(
        listBulletScale = sizeValues.getValue(SizeProperty.LIST_BULLET_SCALE),
        footnoteScale = sizeValues.getValue(SizeProperty.FOOTNOTE_SCALE),
        mathScale = sizeValues.getValue(SizeProperty.MATH_SCALE),
        alertNoteColor = colorValues.getValue(ColorProperty.ALERT_NOTE),
        alertTipColor = colorValues.getValue(ColorProperty.ALERT_TIP),
        alertImportantColor = colorValues.getValue(ColorProperty.ALERT_IMPORTANT),
        alertWarningColor = colorValues.getValue(ColorProperty.ALERT_WARNING),
        alertCautionColor = colorValues.getValue(ColorProperty.ALERT_CAUTION),
        bodyTextColor = colorValues.getValue(ColorProperty.BODY_TEXT),
        headingTextColor = colorValues.getValue(ColorProperty.HEADING_TEXT),
        linkColor = colorValues.getValue(ColorProperty.LINK),
        codeTextColor = colorValues.getValue(ColorProperty.CODE_TEXT),
        codeBackgroundColor = colorValues.getValue(ColorProperty.CODE_BACKGROUND),
        codeBlockCornerRadiusDp = sizeValues.getValue(SizeProperty.CODE_CORNER_RADIUS),
        blockQuoteBarColor = colorValues.getValue(ColorProperty.BLOCK_QUOTE_BAR),
        blockQuoteTextColor = colorValues.getValue(ColorProperty.BLOCK_QUOTE_TEXT),
        blockQuoteBackgroundColor = colorValues.getValue(ColorProperty.BLOCK_QUOTE_BACKGROUND),
        tableBorderColor = colorValues.getValue(ColorProperty.TABLE_BORDER),
        tableHeaderBackgroundColor = colorValues.getValue(ColorProperty.TABLE_HEADER_BACKGROUND),
        bodyFontSizeSp = sizeValues.getValue(SizeProperty.BODY_FONT_SIZE),
        codeFontSizeSp = sizeValues.getValue(SizeProperty.CODE_FONT_SIZE),
        backgroundColor = colorValues.getValue(ColorProperty.VIEW_BACKGROUND)
    )

    companion object {
        private const val TAG = "theme_settings"

        fun show(fragmentManager: FragmentManager, currentTheme: THKMDTheme, onThemeChanged: (THKMDTheme) -> Unit) {
            val sheet = ThemeSettingsSheet()
            sheet.initialTheme = currentTheme
            sheet.onThemeChanged = onThemeChanged
            sheet.show(fragmentManager, TAG)
        }
    }
}
