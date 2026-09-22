package com.thk.mdview

import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.BackgroundColorSpan
import android.text.style.BulletSpan
import android.text.style.LeadingMarginSpan
import android.text.style.QuoteSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import org.commonmark.ext.gfm.strikethrough.Strikethrough
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.ext.gfm.tables.TableCell
import org.commonmark.ext.gfm.tables.TableRow
import org.commonmark.ext.task.list.items.TaskListItemMarker
import org.commonmark.node.AbstractVisitor
import org.commonmark.node.BlockQuote
import org.commonmark.node.BulletList
import org.commonmark.node.Code
import org.commonmark.node.CustomBlock
import org.commonmark.node.CustomNode
import org.commonmark.node.Document
import org.commonmark.node.Emphasis
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.HardLineBreak
import org.commonmark.node.Heading
import org.commonmark.node.Image
import org.commonmark.node.IndentedCodeBlock
import org.commonmark.node.Link
import org.commonmark.node.ListItem
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text
import org.commonmark.node.ThematicBreak

internal class MarkdownSpanVisitor(
    private val builder: SpannableStringBuilder,
    private val linkHandler: (String) -> Boolean
) : AbstractVisitor() {

    private class ListContext(val ordered: Boolean, var index: Int, val level: Int)

    private val listStack = ArrayDeque<ListContext>()

    override fun visit(document: Document) {
        visitChildren(document)
    }

    override fun visit(paragraph: Paragraph) {
        separate()
        visitChildren(paragraph)
    }

    override fun visit(heading: Heading) {
        separate()
        withSpan(StyleSpan(Typeface.BOLD)) {
            withSpan(RelativeSizeSpan(sizeForLevel(heading.level))) {
                visitChildren(heading)
            }
        }
    }

    override fun visit(emphasis: Emphasis) {
        withSpan(StyleSpan(Typeface.ITALIC)) { visitChildren(emphasis) }
    }

    override fun visit(strongEmphasis: StrongEmphasis) {
        withSpan(StyleSpan(Typeface.BOLD)) { visitChildren(strongEmphasis) }
    }

    override fun visit(code: Code) {
        withSpan(BackgroundColorSpan(CODE_BG_COLOR)) {
            withSpan(TypefaceSpan("monospace")) {
                builder.append(code.literal)
            }
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
        withSpan(CodeBlockBackgroundSpan(CODE_BG_COLOR)) {
            withSpan(BackgroundColorSpan(CODE_BG_COLOR)) {
                withSpan(TypefaceSpan("monospace")) {
                    builder.append(content)
                }
            }
        }
    }

    override fun visit(blockQuote: BlockQuote) {
        separate()
        withSpan(QuoteSpan()) { visitChildren(blockQuote) }
    }

    override fun visit(thematicBreak: ThematicBreak) {
        separate()
        builder.append(THEMATIC_BREAK_LINE)
    }

    override fun visit(link: Link) {
        val url = link.destination ?: ""
        withSpan(LinkClickableSpan(url, linkHandler)) { visitChildren(link) }
    }

    override fun visit(image: Image) {
        // v0: images are not loaded; fall back to rendering the alt text as plain text.
        visitChildren(image)
    }

    override fun visit(softLineBreak: SoftLineBreak) {
        builder.append(' ')
    }

    override fun visit(hardLineBreak: HardLineBreak) {
        builder.append('\n')
    }

    override fun visit(text: Text) {
        builder.append(text.literal)
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

    override fun visit(customNode: CustomNode) {
        when (customNode) {
            is Strikethrough -> withSpan(StrikethroughSpan()) { visitChildren(customNode) }
            else -> visitChildren(customNode)
        }
    }

    override fun visit(customBlock: CustomBlock) {
        if (customBlock is TableBlock) {
            renderTableFallback(customBlock)
        } else {
            visitChildren(customBlock)
        }
    }

    private fun renderTableFallback(table: TableBlock) {
        separate()
        val rows = mutableListOf<List<String>>()
        var section: Node? = table.firstChild
        while (section != null) {
            var rowNode: Node? = section.firstChild
            while (rowNode != null) {
                if (rowNode is TableRow) {
                    val cells = mutableListOf<String>()
                    var cellNode: Node? = rowNode.firstChild
                    while (cellNode != null) {
                        if (cellNode is TableCell) {
                            cells.add(plainTextOf(cellNode))
                        }
                        cellNode = cellNode.next
                    }
                    rows.add(cells)
                }
                rowNode = rowNode.next
            }
            section = section.next
        }

        val columnCount = rows.maxOfOrNull { it.size } ?: 0
        val colWidths = IntArray(columnCount)
        for (row in rows) {
            row.forEachIndexed { i, cell -> colWidths[i] = maxOf(colWidths[i], cell.length) }
        }

        val start = builder.length
        rows.forEachIndexed { rowIndex, row ->
            if (rowIndex > 0) builder.append('\n')
            row.forEachIndexed { i, cell ->
                if (i > 0) builder.append("  ")
                builder.append(cell.padEnd(colWidths[i]))
            }
        }
        val end = builder.length
        if (end > start) {
            builder.setSpan(TypefaceSpan("monospace"), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    private fun plainTextOf(node: Node): String {
        val sb = StringBuilder()
        node.accept(object : AbstractVisitor() {
            override fun visit(text: Text) {
                sb.append(text.literal)
            }
        })
        return sb.toString()
    }

    private fun separate() {
        if (builder.isNotEmpty() && builder.last() != '\n') {
            builder.append('\n')
        }
    }

    private inline fun withSpan(span: Any, block: () -> Unit) {
        val start = builder.length
        block()
        val end = builder.length
        if (end > start) {
            builder.setSpan(span, start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    private fun sizeForLevel(level: Int): Float = when (level) {
        1 -> 1.5f
        2 -> 1.4f
        3 -> 1.3f
        4 -> 1.2f
        5 -> 1.1f
        else -> 1.0f
    }

    companion object {
        private const val CODE_BG_COLOR = -0x111112 // light gray, ARGB 0xFFEEEEEE
        private const val INDENT_PX = 36
        private const val BULLET_GAP_PX = 24
        private const val THEMATIC_BREAK_LINE = "────────────────────"
    }
}
