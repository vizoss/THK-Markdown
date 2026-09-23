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
    private val resources = context.resources
    private var previousSource = ""
    private var sealedLength = 0
    private val sealedNodes = mutableListOf<org.commonmark.node.Node>()
    internal var lastParsedCharacters = 0
        private set
    internal var incrementalParsingEnabled = true
    private val blockStart = Regex("^ {0,3}(?:[#>+*_=~`|\\-]|[0-9]+[.)](?: |$))")

    // Conservative incremental path: completed ordinary paragraphs are independent.
    // Global references, extensions and block syntax always use the full parser.
    private fun parse(markdown: String): Document {
        val safe = incrementalParsingEnabled && markdown.none { it in "[]<>$\\`\r\t" } && markdown.lines().none {
            it.startsWith("    ") || blockStart.containsMatchIn(it)
        }
        if (!safe || !markdown.startsWith(previousSource)) {
            sealedLength = 0
            sealedNodes.clear()
        }
        previousSource = markdown
        lastParsedCharacters = 0
        if (!safe) {
            lastParsedCharacters = markdown.length
            return parser.parse(MarkdownExtensions.prepare(markdown)) as Document
        }
        val separator = markdown.lastIndexOf("\n\n")
        val boundary = if (separator < 0) 0 else separator + 2
        if (boundary > sealedLength) {
            val part = markdown.substring(sealedLength, boundary)
            lastParsedCharacters += part.length
            var node = parser.parse(part).firstChild
            while (node != null) { val next = node.next; node.unlink(); sealedNodes.add(node); node = next }
            sealedLength = boundary
        }
        val result = Document()
        sealedNodes.forEach { result.appendChild(it) }
        val tail = markdown.substring(sealedLength)
        lastParsedCharacters += tail.length
        var node = parser.parse(tail).firstChild
        while (node != null) { val next = node.next; result.appendChild(node); node = next }
        return result
    }

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
        previousSource = ""; sealedLength = 0; sealedNodes.clear()
    }

}
