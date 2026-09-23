package com.thk.mdview

import android.content.Context
import org.commonmark.node.Document
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.ext.gfm.tables.TablesExtension
import org.commonmark.ext.task.list.items.TaskListItemsExtension
import org.commonmark.parser.Parser
import org.commonmark.parser.IncludeSourceSpans

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
    private val resources = context.resources
    private var previousSource = ""
    private var sealedLength = 0
    private val sealedNodes = mutableListOf<org.commonmark.node.Node>()
    internal var lastParsedCharacters = 0
        private set
    internal var incrementalParsingEnabled = true
    private var sealedSource = ""

    // Keep two trailing top-level blocks mutable: an unfinished line can become a
    // list marker and merge with the preceding list. Never split a container/fence.
    private fun parse(markdown: String): Document {
        val prepared = MarkdownExtensions.prepare(markdown).replace("\r\n", "\n").replace('\r', '\n')
        // Deliberately over-detect definitions, including escaped/multiline labels.
        val safe = incrementalParsingEnabled && !prepared.contains("]:") && !markdown.contains("[^")
        if (!safe || !markdown.startsWith(previousSource) || !prepared.startsWith(sealedSource)) {
            sealedLength = 0
            sealedNodes.clear()
            sealedSource = ""
        }
        previousSource = markdown
        lastParsedCharacters = 0
        if (!safe) {
            lastParsedCharacters = prepared.length
            return parser.parse(prepared) as Document
        }
        val tail = prepared.substring(sealedLength)
        lastParsedCharacters = tail.length
        val parsed = parser.parse(tail)
        val nodes = mutableListOf<org.commonmark.node.Node>()
        var node = parsed.firstChild
        while (node != null) { nodes.add(node); node = node.next }
        val result = Document()
        sealedNodes.forEach { result.appendChild(it) }
        if (nodes.size > 2) {
            val line = nodes[nodes.size - 2].sourceSpans.firstOrNull()?.lineIndex
            if (line != null && line > 0) {
                var offset = 0
                repeat(line) { offset = tail.indexOf('\n', offset) + 1 }
                sealedNodes.addAll(nodes.dropLast(2))
                sealedLength += offset
                sealedSource = prepared.substring(0, sealedLength)
            }
        }
        nodes.forEach { result.appendChild(it) }
        return result
    }

    private val parser: Parser = Parser.builder()
        .includeSourceSpans(IncludeSourceSpans.BLOCKS)
        .extensions(
            listOf(
                TablesExtension.create(),
                StrikethroughExtension.create(),
                TaskListItemsExtension.create()
            )
        )
        .build()

    override fun render(markdown: String, theme: THKMDTheme, imageBounds: ImageBounds): List<RenderedSegment> {
        val document = parse(markdown)
        val imageContext = ImageRenderContext(
            bounds = imageBounds,
            cornerRadiusPx = theme.codeBlockCornerRadiusDp * density,
            placeholderColor = theme.imagePlaceholderColor,
            clickHandler = imageClickHandler
        )
        val visitor = MarkdownSpanVisitor(theme, density, linkHandler, imageContext, resources.displayMetrics.scaledDensity)
        return visitor.render(document)
    }

    internal fun clearIncrementalState() {
        previousSource = ""; sealedSource = ""; sealedLength = 0; sealedNodes.clear()
    }

}
