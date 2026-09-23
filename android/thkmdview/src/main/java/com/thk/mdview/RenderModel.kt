package com.thk.mdview

/**
 * One top-level segment of a rendered message; see RESEARCH.md §9. Part of the
 * [MarkdownRenderer] contract, so a custom renderer implementation produces these too.
 */
sealed interface RenderedSegment {
    data class TextSegment(
        val spanned: CharSequence,
        val copyableBlocks: List<CopyableBlock> = emptyList()
    ) : RenderedSegment
    data class TableSegment(val table: THKTableData) : RenderedSegment
    /** A ```mermaid fenced block, rendered by [THKMermaidView] instead of as plain code text. */
    data class DiagramSegment(val mermaidSource: String) : RenderedSegment
}

/**
 * A code block or the outermost block quote's plain-text range within a [RenderedSegment.TextSegment]'s
 * `spanned` content — [text] is what a corner copy button (added by THKMDView as a text-segment
 * overlay) copies to the clipboard. A nested (non-outermost) block quote does not get one, matching
 * the existing "only the outermost quote gets the rounded background" rule.
 */
data class CopyableBlock(val range: IntRange, val text: String)

/** Copy formula source, not the inline object's U+FFFC glyph. */
internal fun copyText(text: android.text.Spanned, start: Int, end: Int): String {
    val result = StringBuilder(text.subSequence(start, end).toString())
    text.getSpans(start, end, AsyncImageSpan::class.java).sortedByDescending { text.getSpanStart(it) }.forEach { span ->
        val source = THKMathEngine.source(span.url) ?: return@forEach
        val from = text.getSpanStart(span)
        val to = text.getSpanEnd(span)
        if (from >= start && to <= end) result.replace(from - start, to - start, source)
    }
    return result.toString()
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
