package com.thk.mdview

import android.graphics.Paint
import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.BulletSpan
import android.text.style.ForegroundColorSpan
import android.text.style.LeadingMarginSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.ext.gfm.tables.TableCell
import org.commonmark.ext.gfm.tables.TableHead
import org.commonmark.ext.gfm.tables.TableRow
import org.commonmark.ext.task.list.items.TaskListItemMarker
import org.commonmark.node.AbstractVisitor
import org.commonmark.node.BlockQuote
import org.commonmark.node.BulletList
import org.commonmark.node.CustomBlock
import org.commonmark.node.Document
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.Heading
import org.commonmark.node.HtmlBlock
import org.commonmark.node.IndentedCodeBlock
import org.commonmark.node.ListItem
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.ThematicBreak

/**
 * Walks the top-level block AST and produces an ordered [RenderedSegment] list: as many
 * consecutive non-table blocks as possible merge into one [RenderedSegment.TextSegment]
 * (same span-building strategy as v0), and each [TableBlock] becomes its own
 * [RenderedSegment.TableSegment] — see RESEARCH.md §9. Inline content (bold/italic/code/
 * links/strikethrough/images) is delegated to [InlineSpanBuilder] so table cells and
 * normal block flow share one implementation.
 */
internal class MarkdownSpanVisitor(
    private val theme: THKMDTheme,
    private val densityPx: Float,
    private val linkHandler: (String) -> Boolean,
    private val imageContext: ImageRenderContext
) : AbstractVisitor() {

    private class ListContext(val ordered: Boolean, var index: Int, val level: Int)

    private val segments = mutableListOf<RenderedSegment>()
    private var builder = SpannableStringBuilder()
    private var copyableBlocks = mutableListOf<CopyableBlock>()
    private val listStack = ArrayDeque<ListContext>()
    private var blockQuoteDepth = 0

    // Used only to *measure* list-marker text ("☑ ", "12. ") at the theme's real body
    // size, so OrderedListItemSpan/TaskListItemSpan reserve exactly enough leading margin
    // for what they draw - a fixed guessed width previously overlapped the item text on
    // higher-density screens or larger theme font sizes.
    private val markerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = theme.bodyFontSizeSp * densityPx
    }

    private fun measuredMarkerWidthPx(markerText: String): Int =
        Math.ceil(markerPaint.measureText(markerText).toDouble()).toInt()

    fun render(document: Document): List<RenderedSegment> {
        document.accept(this)
        flushTextSegment()
        return segments
    }

    private fun flushTextSegment() {
        while (builder.isNotEmpty() && builder.last() == '\n') {
            builder.delete(builder.length - 1, builder.length)
        }
        if (builder.isNotEmpty()) {
            segments.add(RenderedSegment.TextSegment(builder, copyableBlocks))
        }
        builder = SpannableStringBuilder()
        copyableBlocks = mutableListOf()
    }

    override fun visit(document: Document) {
        visitChildren(document)
    }

    override fun visit(paragraph: Paragraph) {
        separate()
        InlineSpanBuilder.appendInline(paragraph.firstChild, builder, theme, linkHandler, imageContext)
    }

    override fun visit(heading: Heading) {
        separate()
        val start = builder.length
        InlineSpanBuilder.appendInline(heading.firstChild, builder, theme, linkHandler, imageContext)
        val end = builder.length
        if (end > start) {
            builder.setSpan(StyleSpan(Typeface.BOLD), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            builder.setSpan(RelativeSizeSpan(sizeForLevel(heading.level)), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            builder.setSpan(ForegroundColorSpan(theme.headingTextColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    override fun visit(fencedCodeBlock: FencedCodeBlock) {
        // A ```mermaid fence gets its own dedicated diagram segment (rendered by a real
        // WebView, see THKMermaidView) instead of the normal monospaced code-block path -
        // same flush-and-add-segment pattern already used for tables below.
        if (fencedCodeBlock.info?.trim()?.equals("mermaid", ignoreCase = true) == true) {
            flushTextSegment()
            segments.add(RenderedSegment.DiagramSegment(fencedCodeBlock.literal.trimEnd('\n')))
            return
        }
        renderCodeBlock(fencedCodeBlock.literal)
    }

    override fun visit(indentedCodeBlock: IndentedCodeBlock) {
        renderCodeBlock(indentedCodeBlock.literal)
    }

    private fun renderCodeBlock(literal: String) {
        separate()
        val content = literal.trimEnd('\n')
        val start = builder.length
        builder.append(content)
        val end = builder.length
        if (end == start) return
        copyableBlocks.add(CopyableBlock(start until end, content))
        val cornerRadiusPx = theme.codeBlockCornerRadiusDp * densityPx
        val horizontalPaddingPx = (12 * densityPx).toInt()
        val topPaddingPx = (COPY_BUTTON_TOP_PADDING_DP * densityPx).toInt()
        val bottomPaddingPx = (BLOCK_VERTICAL_PADDING_DP * densityPx).toInt()
        builder.setSpan(
            CodeBlockBackgroundSpan(theme.codeBackgroundColor, cornerRadiusPx, topPaddingPx, bottomPaddingPx, start, end),
            start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        builder.setSpan(CodeBlockPaddingSpan(horizontalPaddingPx), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(ForegroundColorSpan(theme.codeTextColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(TypefaceSpan("monospace"), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(
            RelativeSizeSpan(theme.codeFontSizeSp / theme.bodyFontSizeSp),
            start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }

    override fun visit(blockQuote: BlockQuote) {
        separate()
        val start = builder.length
        val isOutermost = blockQuoteDepth == 0
        blockQuoteDepth++
        // Recursing through visitChildren (not InlineSpanBuilder) lets a nested
        // `> > quote` add its own ThemedQuoteSpan over the inner range, so nested
        // quotes stack as multiple side-by-side bars. Only the outermost span also gets
        // the rounded background fill - see the comment on ThemedQuoteSpan for why.
        visitChildren(blockQuote)
        blockQuoteDepth--
        val end = builder.length
        if (end > start) {
            // Bottom padding shares the same constant as code blocks (BLOCK_VERTICAL_PADDING_DP)
            // so the two block types read as one consistent "padded block" family; bar width
            // and bar-to-text gap are also shared constants - both were previously raw,
            // unscaled pixel values here, which is why the gap looked wrong/inconsistent
            // across densities and didn't match iOS's (differently fixed) bar width. Top
            // padding is taller (COPY_BUTTON_TOP_PADDING_DP) to leave room for the outermost
            // quote's own copy-button overlay without it covering the first line's text.
            builder.setSpan(
                ThemedQuoteSpan(
                    barColor = theme.blockQuoteBarColor,
                    backgroundColor = if (isOutermost) theme.blockQuoteBackgroundColor else null,
                    cornerRadiusPx = theme.codeBlockCornerRadiusDp * densityPx,
                    topPaddingPx = (COPY_BUTTON_TOP_PADDING_DP * densityPx).toInt(),
                    bottomPaddingPx = (BLOCK_VERTICAL_PADDING_DP * densityPx).toInt(),
                    spanStart = start,
                    spanEnd = end,
                    stripeWidthPx = (QUOTE_BAR_WIDTH_DP * densityPx).toInt(),
                    gapWidthPx = (QUOTE_BAR_GAP_DP * densityPx).toInt(),
                    leftInsetPx = (QUOTE_BAR_LEFT_INSET_DP * densityPx).toInt(),
                    barVerticalInsetPx = (QUOTE_BAR_VERTICAL_INSET_DP * densityPx).toInt()
                ),
                start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            builder.setSpan(ForegroundColorSpan(theme.blockQuoteTextColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            // A little extra leading between wrapped/multi-paragraph lines *inside* the
            // quote (distinct from ThemedQuoteSpan's own first/last-line padding above),
            // so multi-line quotes don't read as cramped.
            builder.setSpan(
                QuoteInteriorLineSpacingSpan((QUOTE_INTERIOR_LINE_SPACING_DP * densityPx).toInt(), start, end),
                start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            if (isOutermost) {
                copyableBlocks.add(CopyableBlock(start until end, builder.subSequence(start, end).toString()))
            }
        }
    }

    override fun visit(thematicBreak: ThematicBreak) {
        separate()
        val start = builder.length
        builder.append(' ')
        val end = builder.length
        builder.setSpan(
            ThematicBreakSpan(theme.tableBorderColor, THEMATIC_BREAK_THICKNESS_DP * densityPx),
            start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }

    override fun visit(htmlBlock: HtmlBlock) {
        // Rendered as inert literal text (never interpreted): commonmark-java hands us
        // raw HTML source in .literal, and appending it as a plain CharSequence to a
        // Spanned/TextView never parses it as markup - Html.fromHtml is simply never
        // called anywhere in this pipeline, which is what keeps LLM-generated HTML-
        // looking text (e.g. a stray "<script>") from being live markup.
        separate()
        builder.append(htmlBlock.literal.trimEnd('\n'))
    }

    override fun visit(bulletList: BulletList) {
        separate()
        listStack.addLast(ListContext(ordered = false, index = 0, level = listStack.size))
        visitChildren(bulletList)
        listStack.removeLast()
    }

    override fun visit(orderedList: OrderedList) {
        separate()
        listStack.addLast(
            ListContext(ordered = true, index = orderedList.markerStartNumber - 1, level = listStack.size)
        )
        visitChildren(orderedList)
        listStack.removeLast()
    }

    override fun visit(listItem: ListItem) {
        val ctx = listStack.last()
        ctx.index += 1
        if (builder.isNotEmpty() && builder.last() != '\n') builder.append('\n')
        val start = builder.length

        val taskMarker = listItem.firstChild as? TaskListItemMarker
        val indentPx = (ctx.level * INDENT_DP * densityPx).toInt()
        val gapPx = (BULLET_GAP_DP * densityPx).toInt()
        val marginSpans = mutableListOf<Any>(LeadingMarginSpan.Standard(indentPx))
        marginSpans += when {
            taskMarker != null -> {
                val glyph = if (taskMarker.isChecked) "☑" else "☐"
                TaskListItemSpan(taskMarker.isChecked, measuredMarkerWidthPx(glyph), gapPx)
            }
            ctx.ordered -> OrderedListItemSpan(ctx.index, measuredMarkerWidthPx("${ctx.index}."), gapPx)
            else -> BulletSpan(gapPx)
        }

        var child: Node? = if (taskMarker != null) listItem.firstChild.next else listItem.firstChild
        while (child != null) {
            child.accept(this)
            child = child.next
        }

        var end = builder.length
        if (end == start) {
            builder.append(' ')
            end = builder.length
        }
        for (span in marginSpans) {
            builder.setSpan(span, start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    override fun visit(customBlock: CustomBlock) {
        if (customBlock is TableBlock) {
            flushTextSegment()
            segments.add(RenderedSegment.TableSegment(buildTableData(customBlock)))
        } else {
            visitChildren(customBlock)
        }
    }

    private fun buildTableData(table: TableBlock): THKTableData {
        val alignments = mutableListOf<THKTableAlignment>()
        val headerCells = mutableListOf<CharSequence>()
        val bodyRows = mutableListOf<List<CharSequence>>()

        var section: Node? = table.firstChild
        while (section != null) {
            val isHead = section is TableHead
            var rowNode: Node? = section.firstChild
            while (rowNode != null) {
                if (rowNode is TableRow) {
                    val cells = mutableListOf<CharSequence>()
                    var cellNode: Node? = rowNode.firstChild
                    while (cellNode != null) {
                        if (cellNode is TableCell) {
                            val cellBuilder = SpannableStringBuilder()
                            InlineSpanBuilder.appendInline(cellNode.firstChild, cellBuilder, theme, linkHandler, imageContext)
                            cells.add(cellBuilder)
                            if (isHead) alignments.add(mapAlignment(cellNode.alignment))
                        }
                        cellNode = cellNode.next
                    }
                    if (isHead) headerCells.addAll(cells) else bodyRows.add(cells)
                }
                rowNode = rowNode.next
            }
            section = section.next
        }
        return THKTableData(alignments, headerCells, bodyRows)
    }

    private fun mapAlignment(alignment: TableCell.Alignment?): THKTableAlignment = when (alignment) {
        TableCell.Alignment.CENTER -> THKTableAlignment.CENTER
        TableCell.Alignment.RIGHT -> THKTableAlignment.END
        else -> THKTableAlignment.START
    }

    // Ensures the buffer ends with a full blank line (not just a single line break) before
    // a new sibling block starts, so paragraph/heading/list/code-block/quote spacing
    // matches iOS's equivalent top-level block joiner, which inserts a blank "\n\n"
    // between siblings (see SwiftMarkdownRenderer.joinBlocks) - a single '\n' here left
    // Android's block-to-block gaps visibly tighter than iOS's.
    //
    // Inside a block quote (blockQuoteDepth > 0) or a list (listStack not empty) this
    // intentionally stays tight (a single '\n', no blank line) instead. A quote's vertical
    // rhythm comes entirely from QuoteInteriorLineSpacingSpan's flat, uniform per-line
    // spacing, matching iOS's joinBlocksTightly used for the same reason - a blank-line
    // gap between e.g. two paragraphs inside the same quote would make that boundary
    // visibly larger-gapped than an ordinary wrapped line. Lists need the same treatment
    // because commonmark-java wraps every list item's text in a Paragraph node even for a
    // "tight" list - visit(paragraph) calling separate() unconditionally would otherwise
    // inject a blank line between every pair of list items (each item's own content is a
    // Paragraph), not just between top-level sibling blocks.
    private fun separate() {
        if (builder.isEmpty()) return
        if (blockQuoteDepth > 0 || listStack.isNotEmpty()) {
            if (builder.last() != '\n') builder.append('\n')
            return
        }
        while (builder.isNotEmpty() && builder.last() == '\n') {
            builder.delete(builder.length - 1, builder.length)
        }
        if (builder.isNotEmpty()) {
            builder.append("\n\n")
        }
    }

    private fun sizeForLevel(level: Int): Float = when (level) {
        1 -> 1.6f
        2 -> 1.4f
        3 -> 1.25f
        4 -> 1.15f
        5 -> 1.05f
        else -> 1.0f
    }

    companion object {
        private const val INDENT_DP = 22f
        private const val BULLET_GAP_DP = 8f
        // Shared with code blocks so both "padded block" types feel consistent, and kept
        // numerically identical to iOS's equivalent constants (see THKMDTheme.swift /
        // MarkdownRenderer.swift comments there) for cross-platform visual parity.
        private const val BLOCK_VERTICAL_PADDING_DP = 8f
        // Matches THKMDView.TextSegmentFrame's COPY_BUTTON_SIZE_DP(32) + 2 *
        // COPY_BUTTON_MARGIN_DP(4) - and iOS's equivalent THKCopyButtonMetrics.
        // topPaddingReserve - so the button has somewhere to sit above the block's first
        // line of real text instead of on top of it.
        private const val COPY_BUTTON_TOP_PADDING_DP = 40f
        private const val QUOTE_BAR_WIDTH_DP = 4f
        private const val QUOTE_BAR_GAP_DP = 12f
        private const val QUOTE_BAR_LEFT_INSET_DP = 2f
        private const val QUOTE_BAR_VERTICAL_INSET_DP = 3f
        private const val QUOTE_INTERIOR_LINE_SPACING_DP = 2f
        private const val THEMATIC_BREAK_THICKNESS_DP = 1.5f
    }
}
