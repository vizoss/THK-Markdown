package com.thk.mdview.sample

import com.thk.mdview.THKMDTheme

/** A visibly non-default theme so the sample can prove `THKMDView.theme = ...` alone
 *  re-renders already-bound bubbles, with no fresh `setMarkdown` call. */
val ALT_THEME: THKMDTheme = THKMDTheme(
    bodyTextColor = 0xFF2B2118.toInt(),
    headingTextColor = 0xFF7A3E00.toInt(),
    linkColor = 0xFFB3541E.toInt(),
    codeTextColor = 0xFF5C3D00.toInt(),
    codeBackgroundColor = 0xFFFCE9C8.toInt(),
    codeBlockCornerRadiusDp = 10f,
    blockQuoteBarColor = 0xFFDA9A3C.toInt(),
    blockQuoteTextColor = 0xFF7A5A2E.toInt(),
    blockQuoteBackgroundColor = 0xFFFBF1DE.toInt(),
    tableBorderColor = 0xFFDA9A3C.toInt(),
    tableHeaderBackgroundColor = 0xFFF6DDB0.toInt(),
    bodyFontSizeSp = 15f,
    codeFontSizeSp = 13f
)

// Markdown content lives exclusively in ios/Fixtures/data/p0.json, shared by both demos.
