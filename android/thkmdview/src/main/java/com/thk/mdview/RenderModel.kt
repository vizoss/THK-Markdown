package com.thk.mdview

/**
 * One top-level segment of a rendered message; see RESEARCH.md §9. Part of the
 * [MarkdownRenderer] contract, so a custom renderer implementation produces these too.
 */
sealed interface RenderedSegment {
    data class TextSegment(val spanned: CharSequence) : RenderedSegment
    data class TableSegment(val table: THKTableData) : RenderedSegment
}

enum class THKTableAlignment { START, CENTER, END }

/** A fully-rendered GFM table: cell content is already inline-Markdown-spanned. */
data class THKTableData(
    val columnAlignments: List<THKTableAlignment>,
    val headerRow: List<CharSequence>,
    val bodyRows: List<List<CharSequence>>
)

/** Max box a `![]()` image is allowed to occupy; see [AsyncImageSpan]. */
data class ImageBounds(val maxWidthPx: Int, val maxHeightPx: Int)
