package com.thk.mdview

import android.text.SpannableStringBuilder
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.ext.gfm.tables.TablesExtension
import org.commonmark.ext.task.list.items.TaskListItemsExtension
import org.commonmark.parser.Parser

interface MarkdownRenderer {
    fun render(markdown: String): CharSequence
}

class DefaultMarkdownRenderer(
    private val linkHandler: (String) -> Boolean = { false }
) : MarkdownRenderer {

    private val parser: Parser = Parser.builder()
        .extensions(
            listOf(
                TablesExtension.create(),
                StrikethroughExtension.create(),
                TaskListItemsExtension.create()
            )
        )
        .build()

    override fun render(markdown: String): CharSequence {
        val document = parser.parse(markdown)
        val builder = SpannableStringBuilder()
        document.accept(MarkdownSpanVisitor(builder, linkHandler))
        while (builder.isNotEmpty() && builder.last() == '\n') {
            builder.delete(builder.length - 1, builder.length)
        }
        return builder
    }
}
