package com.thk.mdview

import android.content.Context
import org.commonmark.node.Document
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.ext.gfm.tables.TablesExtension
import org.commonmark.ext.task.list.items.TaskListItemsExtension
import org.commonmark.parser.Parser

/** Pluggable Markdown -> segment renderer; swap in via [THKMDView.setMarkdownRenderer]. */
interface MarkdownRenderer {
    /**
     * Parses [markdown] and returns the ordered top-level segments to display (see
     * RESEARCH.md §9). [theme] and [imageBounds] are supplied per call (rather than
     * fixed at construction) because both can change without the caller re-invoking
     * `setMarkdown` — [THKMDView] re-renders the last buffer content on a theme change
     * or a view resize.
     */
    fun render(markdown: String, theme: THKMDTheme, imageBounds: ImageBounds): List<RenderedSegment>
}

/** Default [MarkdownRenderer]: commonmark-java (+ GFM tables/strikethrough/task-lists). */
class DefaultMarkdownRenderer(
    context: Context,
    private val linkHandler: (String) -> Boolean = { false },
    private val imageClickHandler: (String) -> Boolean = { false }
) : MarkdownRenderer {

    private val density = context.resources.displayMetrics.density

    private val parser: Parser = Parser.builder()
        .extensions(
            listOf(
                TablesExtension.create(),
                StrikethroughExtension.create(),
                TaskListItemsExtension.create()
            )
        )
        .build()

    override fun render(markdown: String, theme: THKMDTheme, imageBounds: ImageBounds): List<RenderedSegment> {
        val document = parser.parse(MarkdownExtensions.prepare(markdown)) as Document
        val imageContext = ImageRenderContext(
            bounds = imageBounds,
            cornerRadiusPx = theme.codeBlockCornerRadiusDp * density,
            placeholderColor = theme.imagePlaceholderColor,
            clickHandler = imageClickHandler
        )
        val visitor = MarkdownSpanVisitor(theme, density, linkHandler, imageContext)
        return visitor.render(document)
    }

}
