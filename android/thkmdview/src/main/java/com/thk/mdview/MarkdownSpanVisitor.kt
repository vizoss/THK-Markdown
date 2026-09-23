package com.thk.mdview

import android.graphics.Paint
import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableStringBuilder
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
    private val imageContext: ImageRenderContext,
    private val scaledDensityPx: Float = densityPx
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
        // Trailing newlines inside a copyable block belong to that block. Removing
        // them after collecting ranges invalidates streaming states (e.g. an empty fence).
        while (builder.isNotEmpty() && builder.last() == '\n' &&
            copyableBlocks.none { builder.length - 1 in it.range }) {
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
        if (blockQuoteDepth == 0 && listStack.isEmpty() &&
            fencedCodeBlock.info?.trim()?.equals("mermaid", ignoreCase = true) == true) {
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
        val content = literal.trimEnd('\n')
        // Empty fences must not flush surrounding text or insert a separator.
        if (content.isEmpty()) return
        val standalone = blockQuoteDepth == 0 && listStack.isEmpty()
        if (standalone) flushTextSegment()
        separate()
        val start = builder.length
        builder.append(content)
        val end = builder.length
        if (end == start) return
        copyableBlocks.add(CopyableBlock(start until end, content))
        val cornerRadiusPx = theme.codeBlockCornerRadiusDp * densityPx
        val horizontalPaddingPx = (12 * densityPx).toInt()
        val topPaddingPx = if (standalone) 0 else (BLOCK_VERTICAL_PADDING_DP * densityPx).toInt()
        val bottomPaddingPx = if (standalone) 0 else (BLOCK_VERTICAL_PADDING_DP * densityPx).toInt()
        builder.setSpan(
            CodeBlockBackgroundSpan(
                theme.codeBackgroundColor, cornerRadiusPx, topPaddingPx, bottomPaddingPx, start, end,
                copyButtonGutterPx = (40 * densityPx).toInt(), containerBackground = standalone
            ),
            start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        builder.setSpan(CodeBlockPaddingSpan(horizontalPaddingPx), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(ForegroundColorSpan(theme.codeTextColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(TypefaceSpan("monospace"), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(
            RelativeSizeSpan(theme.codeFontSizeSp / theme.bodyFontSizeSp),
            start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        if (standalone) flushTextSegment()
    }

    override fun visit(blockQuote: BlockQuote) {
        val marker = (blockQuote.firstChild as? org.commonmark.node.Paragraph)?.firstChild as? org.commonmark.node.Text
        val originalMarker = marker?.literal.orEmpty()
        val kind = if (originalMarker.startsWith("[!") && originalMarker.endsWith("]")) originalMarker.drop(2).dropLast(1) else ""
        val alertColor = if (blockQuoteDepth == 0 && listStack.isEmpty()) theme.alertColor(kind) else null
        // A standalone quote gets its own text container, leaving a real right-hand
        // gutter for the copy button without narrowing the surrounding paragraphs.
        val standalone = blockQuoteDepth == 0 && listStack.isEmpty()
        if (standalone) flushTextSegment()
        separate()
        val start = builder.length
        val isOutermost = blockQuoteDepth == 0
        blockQuoteDepth++
        // Recursing through visitChildren (not InlineSpanBuilder) lets a nested
        // `> > quote` add its own ThemedQuoteSpan over the inner range, so nested
        // quotes stack as multiple side-by-side bars. Only the outermost span also gets
        // the rounded background fill - see the comment on ThemedQuoteSpan for why.
        if (alertColor != null) marker?.literal = kind
        val softBreak = if (alertColor != null) marker?.next as? org.commonmark.node.SoftLineBreak else null
        val hardBreak = softBreak?.let { org.commonmark.node.HardLineBreak().also { replacement -> it.insertBefore(replacement); it.unlink() } }
        visitChildren(blockQuote)
        if (hardBreak != null) { hardBreak.insertBefore(softBreak); hardBreak.unlink() }
        if (alertColor != null) marker?.literal = originalMarker
        blockQuoteDepth--
        val end = builder.length
        if (end > start) {
            // Standalone quotes use view padding rather than growing a line's font
            // metrics: Android can carry those enlarged metrics into wrapped lines.
            builder.setSpan(
                ThemedQuoteSpan(
                    barColor = alertColor ?: theme.blockQuoteBarColor,
                    backgroundColor = if (isOutermost) theme.blockQuoteBackgroundColor else null,
                    cornerRadiusPx = theme.codeBlockCornerRadiusDp * densityPx,
                    topPaddingPx = if (standalone) 0 else (BLOCK_VERTICAL_PADDING_DP * densityPx).toInt(),
                    bottomPaddingPx = if (standalone) 0 else (BLOCK_VERTICAL_PADDING_DP * densityPx).toInt(),
                    spanStart = start,
                    spanEnd = end,
                    stripeWidthPx = (QUOTE_BAR_WIDTH_DP * densityPx).toInt(),
                    gapWidthPx = (QUOTE_BAR_GAP_DP * densityPx).toInt(),
                    leftInsetPx = (QUOTE_BAR_LEFT_INSET_DP * densityPx).toInt(),
                    barVerticalInsetPx = (QUOTE_BAR_VERTICAL_INSET_DP * densityPx).toInt(),
                    copyButtonGutterPx = if (isOutermost) (40 * densityPx).toInt() else 0,
                    containerBackground = standalone,
                    nestedTopPaddingPx = if (blockQuoteDepth == 1) (10 * densityPx).toInt() else 0,
                    nestedBottomPaddingPx = if (blockQuoteDepth == 1) (10 * densityPx).toInt() else 0
                ),
                start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE or
                    ((254 - blockQuoteDepth - listStack.size).coerceAtLeast(1) shl Spannable.SPAN_PRIORITY_SHIFT)
            )
            // Preserve explicit code/link/footnote colors inside an alert/quote.
            var colorStart = start
            while (colorStart < end) {
                val colorEnd = builder.nextSpanTransition(colorStart, end, ForegroundColorSpan::class.java)
                if (builder.getSpans(colorStart, colorEnd, ForegroundColorSpan::class.java).isEmpty()) {
                    builder.setSpan(ForegroundColorSpan(theme.blockQuoteTextColor), colorStart, colorEnd, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                colorStart = colorEnd
            }
            if (alertColor != null) {
                builder.setSpan(ForegroundColorSpan(alertColor), start, start + kind.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                builder.setSpan(StyleSpan(android.graphics.Typeface.BOLD), start, start + kind.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            // A little extra leading between wrapped/multi-paragraph lines *inside* the
            // quote (distinct from ThemedQuoteSpan's own first/last-line padding above),
            // so multi-line quotes don't read as cramped.
            if (isOutermost && !standalone) builder.setSpan(
                QuoteInteriorLineSpacingSpan((QUOTE_INTERIOR_LINE_SPACING_DP * densityPx).toInt(), start, end),
                start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            if (isOutermost) {
                copyableBlocks.add(CopyableBlock(start until end, copyText(builder, start, end)))
            }
        }
        if (standalone) flushTextSegment()
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
        val markerSpan: LeadingMarginSpan = when {
            taskMarker != null -> {
                TaskListItemSpan(taskMarker.isChecked, (markerPaint.textSize * 0.85f).toInt(), (4 * densityPx).toInt())
            }
            ctx.ordered -> OrderedListItemSpan(ctx.index, measuredMarkerWidthPx("${ctx.index}."), gapPx)
            else -> ThemedBulletSpan(
                theme.bodyFontSizeSp * scaledDensityPx *
                    (theme.listBulletScale.takeIf { it.isFinite() && it > 0f } ?: THKMDTheme.Default.listBulletScale),
                gapPx
            )
        }

        var child: Node? = if (taskMarker != null) listItem.firstChild.next else listItem.firstChild
        val ownRanges = mutableListOf<IntRange>()
        while (child != null) {
            val childStart = builder.length
            child.accept(this)
            // Descendant lists already own their absolute depth and marker margin.
            // Never apply ancestor margins over them a second time.
            if (child !is BulletList && child !is OrderedList && builder.length > childStart) {
                val contentStart = if (builder[childStart] == '\n') childStart + 1 else childStart
                if (contentStart < builder.length) ownRanges += contentStart until builder.length
            }
            child = child.next
        }

        var end = builder.length
        if (end == start) {
            builder.append(' ')
            end = builder.length
            ownRanges += start until end
        }
        for ((index, range) in ownRanges.withIndex()) {
            // Android draws leading margins in priority order. Follow container
            // nesting, not span type: quote > list and list > quote both occur.
            val priority = (254 - blockQuoteDepth - ctx.level).coerceAtLeast(1)
            val flags = Spannable.SPAN_EXCLUSIVE_EXCLUSIVE or (priority shl Spannable.SPAN_PRIORITY_SHIFT)
            builder.setSpan(LeadingMarginSpan.Standard(indentPx), range.first, range.last + 1, flags)
            val span = if (index == 0) markerSpan else LeadingMarginSpan.Standard(markerSpan.getLeadingMargin(true))
            builder.setSpan(span, range.first, range.last + 1, flags)
        }
    }

    override fun visit(customBlock: CustomBlock) {
        if (customBlock is TableBlock) {
            if (blockQuoteDepth > 0 || listStack.isNotEmpty()) {
                separate()
                val table = buildTableData(customBlock)
                (listOf(table.headerRow) + table.bodyRows).forEachIndexed { row, cells ->
                    if (row > 0) builder.append('\n')
                    cells.forEachIndexed { column, cell ->
                        if (column > 0) builder.append(" | ")
                        val cellStart = builder.length
                        builder.append(cell)
                        if (row == 0 && builder.length > cellStart) {
                            builder.setSpan(StyleSpan(Typeface.BOLD), cellStart, builder.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                        }
                    }
                }
                return
            }
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
        1 -> theme.heading1Scale
        2 -> theme.heading2Scale
        3 -> theme.heading3Scale
        4 -> theme.heading4Scale
        5 -> theme.heading5Scale
        else -> theme.heading6Scale
    }

    companion object {
        private const val INDENT_DP = 20f
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
        private const val QUOTE_BAR_GAP_DP = 8f
        private const val QUOTE_BAR_LEFT_INSET_DP = 8f
        private const val QUOTE_BAR_VERTICAL_INSET_DP = 3f
        private const val QUOTE_INTERIOR_LINE_SPACING_DP = 2f
        private const val THEMATIC_BREAK_THICKNESS_DP = 1.5f
    }
}
