package com.thk.mdview

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
    private val listStack = ArrayDeque<ListContext>()

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
            segments.add(RenderedSegment.TextSegment(builder))
        }
        builder = SpannableStringBuilder()
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
        val cornerRadiusPx = theme.codeBlockCornerRadiusDp * densityPx
        val paddingPx = (12 * densityPx).toInt()
        builder.setSpan(
            CodeBlockBackgroundSpan(theme.codeBackgroundColor, cornerRadiusPx, start, end),
            start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        builder.setSpan(CodeBlockPaddingSpan(paddingPx), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
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
        // Recursing through visitChildren (not InlineSpanBuilder) lets a nested
        // `> > quote` add its own ThemedQuoteSpan over the inner range, so nested
        // quotes stack as multiple side-by-side bars rather than needing depth tracking.
        visitChildren(blockQuote)
        val end = builder.length
        if (end > start) {
            builder.setSpan(ThemedQuoteSpan(theme.blockQuoteBarColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            builder.setSpan(ForegroundColorSpan(theme.blockQuoteTextColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    override fun visit(thematicBreak: ThematicBreak) {
        separate()
        val start = builder.length
        builder.append(THEMATIC_BREAK_LINE)
        val end = builder.length
        builder.setSpan(ForegroundColorSpan(theme.tableBorderColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
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
        val marginSpans = mutableListOf<Any>(LeadingMarginSpan.Standard(ctx.level * INDENT_PX))
        marginSpans += when {
            taskMarker != null -> TaskListItemSpan(taskMarker.isChecked, BULLET_GAP_PX)
            ctx.ordered -> OrderedListItemSpan(ctx.index, BULLET_GAP_PX)
            else -> BulletSpan(BULLET_GAP_PX)
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

    private fun separate() {
        if (builder.isNotEmpty() && builder.last() != '\n') {
            builder.append('\n')
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
        private const val INDENT_PX = 36
        private const val BULLET_GAP_PX = 24
        private const val THEMATIC_BREAK_LINE = "────────────────────"
    }
}
