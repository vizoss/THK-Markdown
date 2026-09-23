package com.thk.mdview.sample

import android.content.Context
import com.thk.mdview.THKMDTheme

/** Demo-only, versioned local preferences. Missing/invalid values retain defaults. */
object DemoThemeStore {
    private fun preferences(context: Context) = context.getSharedPreferences("markdown_theme_v1", Context.MODE_PRIVATE)

    fun load(context: Context): THKMDTheme {
        val prefs = preferences(context)
        val defaults = THKMDTheme.Default
        fun color(key: String, fallback: Int): Int = try { prefs.getInt(key, fallback) } catch (_: ClassCastException) { fallback }
        fun size(key: String, fallback: Float): Float = try {
            prefs.getFloat(key, fallback).takeIf { it.isFinite() && it >= 0f && (it > 0f || key == "codeBlockCornerRadiusDp") } ?: fallback
        } catch (_: ClassCastException) { fallback }
        return defaults.copy(
            listBulletScale = size("listBulletScale", defaults.listBulletScale),
            footnoteScale = size("footnoteScale", defaults.footnoteScale),
            mathScale = size("mathScale", defaults.mathScale),
            alertNoteColor = color("alertNoteColor", defaults.alertNoteColor),
            alertTipColor = color("alertTipColor", defaults.alertTipColor),
            alertImportantColor = color("alertImportantColor", defaults.alertImportantColor),
            alertWarningColor = color("alertWarningColor", defaults.alertWarningColor),
            alertCautionColor = color("alertCautionColor", defaults.alertCautionColor),
            bodyTextColor = color("bodyTextColor", defaults.bodyTextColor),
            headingTextColor = color("headingTextColor", defaults.headingTextColor),
            linkColor = color("linkColor", defaults.linkColor),
            codeTextColor = color("codeTextColor", defaults.codeTextColor),
            codeBackgroundColor = color("codeBackgroundColor", defaults.codeBackgroundColor),
            blockQuoteBarColor = color("blockQuoteBarColor", defaults.blockQuoteBarColor),
            blockQuoteTextColor = color("blockQuoteTextColor", defaults.blockQuoteTextColor),
            blockQuoteBackgroundColor = color("blockQuoteBackgroundColor", defaults.blockQuoteBackgroundColor),
            tableBorderColor = color("tableBorderColor", defaults.tableBorderColor),
            tableHeaderBackgroundColor = color("tableHeaderBackgroundColor", defaults.tableHeaderBackgroundColor),
            backgroundColor = color("backgroundColor", defaults.backgroundColor),
            imagePlaceholderColor = color("imagePlaceholderColor", defaults.imagePlaceholderColor),
            codeBlockCornerRadiusDp = size("codeBlockCornerRadiusDp", defaults.codeBlockCornerRadiusDp),
            bodyFontSizeSp = size("bodyFontSizeSp", defaults.bodyFontSizeSp),
            codeFontSizeSp = size("codeFontSizeSp", defaults.codeFontSizeSp),
            heading1Scale = size("heading1Scale", defaults.heading1Scale),
            heading2Scale = size("heading2Scale", defaults.heading2Scale),
            heading3Scale = size("heading3Scale", defaults.heading3Scale),
            heading4Scale = size("heading4Scale", defaults.heading4Scale),
            heading5Scale = size("heading5Scale", defaults.heading5Scale),
            heading6Scale = size("heading6Scale", defaults.heading6Scale)
        )
    }

    fun save(context: Context, theme: THKMDTheme) {
        preferences(context).edit()
            .putFloat("listBulletScale", theme.listBulletScale)
            .putFloat("footnoteScale", theme.footnoteScale)
            .putFloat("mathScale", theme.mathScale)
            .putInt("alertNoteColor", theme.alertNoteColor)
            .putInt("alertTipColor", theme.alertTipColor)
            .putInt("alertImportantColor", theme.alertImportantColor)
            .putInt("alertWarningColor", theme.alertWarningColor)
            .putInt("alertCautionColor", theme.alertCautionColor)
            .putInt("bodyTextColor", theme.bodyTextColor)
            .putInt("headingTextColor", theme.headingTextColor)
            .putInt("linkColor", theme.linkColor)
            .putInt("codeTextColor", theme.codeTextColor)
            .putInt("codeBackgroundColor", theme.codeBackgroundColor)
            .putInt("blockQuoteBarColor", theme.blockQuoteBarColor)
            .putInt("blockQuoteTextColor", theme.blockQuoteTextColor)
            .putInt("blockQuoteBackgroundColor", theme.blockQuoteBackgroundColor)
            .putInt("tableBorderColor", theme.tableBorderColor)
            .putInt("tableHeaderBackgroundColor", theme.tableHeaderBackgroundColor)
            .putInt("backgroundColor", theme.backgroundColor)
            .putInt("imagePlaceholderColor", theme.imagePlaceholderColor)
            .putFloat("codeBlockCornerRadiusDp", theme.codeBlockCornerRadiusDp)
            .putFloat("bodyFontSizeSp", theme.bodyFontSizeSp)
            .putFloat("codeFontSizeSp", theme.codeFontSizeSp)
            .putFloat("heading1Scale", theme.heading1Scale)
            .putFloat("heading2Scale", theme.heading2Scale)
            .putFloat("heading3Scale", theme.heading3Scale)
            .putFloat("heading4Scale", theme.heading4Scale)
            .putFloat("heading5Scale", theme.heading5Scale)
            .putFloat("heading6Scale", theme.heading6Scale)
            .apply()
    }
}
