package com.thk.mdview

import android.graphics.Color

/**
 * Immutable color/text configuration for [THKMDView]. Assigning a new value to
 * [THKMDView.theme] re-renders the current content with it — callers never need to
 * call `setMarkdown` again just to pick up a theme change.
 */
data class THKMDTheme(
    val bodyTextColor: Int,
    val headingTextColor: Int,
    val linkColor: Int,
    val codeTextColor: Int,
    val codeBackgroundColor: Int,
    val codeBlockCornerRadiusDp: Float,
    val blockQuoteBarColor: Int,
    val blockQuoteTextColor: Int,
    val blockQuoteBackgroundColor: Int,
    val tableBorderColor: Int,
    val tableHeaderBackgroundColor: Int,
    val bodyFontSizeSp: Float,
    val codeFontSizeSp: Float,
    // Background painted behind the whole view; transparent by default so a host's
    // chat-bubble background (e.g. a MaterialCardView) shows through unless overridden.
    val backgroundColor: Int = Color.TRANSPARENT
) {
    companion object {
        val Default = THKMDTheme(
            bodyTextColor = 0xFF1C1C1E.toInt(),
            headingTextColor = 0xFF1C1C1E.toInt(),
            linkColor = 0xFF0A84FF.toInt(),
            codeTextColor = 0xFF3A3A3C.toInt(),
            codeBackgroundColor = 0xFFEEEEEE.toInt(),
            codeBlockCornerRadiusDp = 8f,
            blockQuoteBarColor = 0xFFC7C7CC.toInt(),
            blockQuoteTextColor = 0xFF3A3A3C.toInt(),
            blockQuoteBackgroundColor = 0xFFF5F5F6.toInt(),
            tableBorderColor = 0xFFD1D1D6.toInt(),
            tableHeaderBackgroundColor = 0xFFEFEFF4.toInt(),
            bodyFontSizeSp = 15f,
            codeFontSizeSp = 13f
        )
    }
}
