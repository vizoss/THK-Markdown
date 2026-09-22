package com.thk.mdview

import android.content.Context
import android.text.Spannable
import android.text.style.BackgroundColorSpan
import android.text.style.BulletSpan
import android.text.style.ClickableSpan
import android.text.style.LineBackgroundSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DefaultMarkdownRendererTest {

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val theme = THKMDTheme.Default
    private val bounds = ImageBounds(800, 600)

    private fun renderer(
        linkHandler: (String) -> Boolean = { false },
        imageClickHandler: (String) -> Boolean = { false }
    ) = DefaultMarkdownRenderer(context, linkHandler, imageClickHandler)

    private fun textSegments(markdown: String, r: DefaultMarkdownRenderer = renderer()): List<RenderedSegment.TextSegment> =
        r.render(markdown, theme, bounds).filterIsInstance<RenderedSegment.TextSegment>()

    private fun onlyText(markdown: String, r: DefaultMarkdownRenderer = renderer()): Spannable {
        val segments = r.render(markdown, theme, bounds)
        val text = segments.single() as RenderedSegment.TextSegment
        return text.spanned as Spannable
    }

    @Test
    fun bold() {
        val spanned = onlyText("**bold**")
        assertThat(spanned.toString()).isEqualTo("bold")
        val spans = spanned.getSpans(0, spanned.length, StyleSpan::class.java)
        assertThat(spans.any { it.style == android.graphics.Typeface.BOLD }).isTrue()
    }

    @Test
    fun italic() {
        val spanned = onlyText("*italic*")
        assertThat(spanned.toString()).isEqualTo("italic")
        val spans = spanned.getSpans(0, spanned.length, StyleSpan::class.java)
        assertThat(spans.any { it.style == android.graphics.Typeface.ITALIC }).isTrue()
    }

    @Test
    fun boldItalicCombined() {
        val spanned = onlyText("***bold italic***")
        assertThat(spanned.toString()).isEqualTo("bold italic")
        val styles = spanned.getSpans(0, spanned.length, StyleSpan::class.java).map { it.style }.toSet()
        assertThat(styles).containsAtLeast(android.graphics.Typeface.BOLD, android.graphics.Typeface.ITALIC)
    }

    @Test
    fun strikethrough() {
        val spanned = onlyText("~~gone~~")
        assertThat(spanned.toString()).isEqualTo("gone")
        assertThat(spanned.getSpans(0, spanned.length, StrikethroughSpan::class.java)).isNotEmpty()
    }

    @Test
    fun inlineCode() {
        val spanned = onlyText("`code`")
        assertThat(spanned.toString()).isEqualTo("code")
        assertThat(spanned.getSpans(0, spanned.length, TypefaceSpan::class.java)).isNotEmpty()
        assertThat(spanned.getSpans(0, spanned.length, BackgroundColorSpan::class.java)).isNotEmpty()
    }

    @Test
    fun fencedCodeBlockWithLanguage() {
        val spanned = onlyText("```kotlin\nfun main() {}\n```")
        assertThat(spanned.toString()).isEqualTo("fun main() {}")
        assertThat(spanned.getSpans(0, spanned.length, LineBackgroundSpan::class.java)).isNotEmpty()
        assertThat(spanned.getSpans(0, spanned.length, TypefaceSpan::class.java)).isNotEmpty()
    }

    @Test
    fun fencedCodeBlockWithoutLanguage() {
        val spanned = onlyText("```\nfun main() {}\n```")
        assertThat(spanned.toString()).isEqualTo("fun main() {}")
        assertThat(spanned.getSpans(0, spanned.length, LineBackgroundSpan::class.java)).isNotEmpty()
    }

    @Test
    fun indentedCodeBlock() {
        val spanned = onlyText("    indented code")
        assertThat(spanned.toString()).isEqualTo("indented code")
        assertThat(spanned.getSpans(0, spanned.length, LineBackgroundSpan::class.java)).isNotEmpty()
        assertThat(spanned.getSpans(0, spanned.length, TypefaceSpan::class.java)).isNotEmpty()
    }

    @Test
    fun heading() {
        val spanned = onlyText("# Heading")
        assertThat(spanned.toString()).isEqualTo("Heading")
        val sizeSpans = spanned.getSpans(0, spanned.length, RelativeSizeSpan::class.java)
        assertThat(sizeSpans).isNotEmpty()
        assertThat(sizeSpans[0].sizeChange).isGreaterThan(1.0f)
        val styleSpans = spanned.getSpans(0, spanned.length, StyleSpan::class.java)
        assertThat(styleSpans.any { it.style == android.graphics.Typeface.BOLD }).isTrue()
    }

    @Test
    fun headingLevelsOneThroughSixAreAllDistinctSizes() {
        val sizes = (1..6).map { level ->
            val markers = "#".repeat(level)
            val spanned = onlyText("$markers H$level")
            spanned.getSpans(0, spanned.length, RelativeSizeSpan::class.java).first().sizeChange
        }
        assertThat(sizes).isInOrder(Comparator.reverseOrder<Float>())
        assertThat(sizes.toSet()).hasSize(6)
    }

    @Test
    fun paragraphSoftLineBreakBecomesASpace() {
        val spanned = onlyText("line one\nline two")
        assertThat(spanned.toString()).isEqualTo("line one line two")
    }

    @Test
    fun hardLineBreakViaTrailingBackslashBecomesNewline() {
        val spanned = onlyText("line one\\\nline two")
        assertThat(spanned.toString()).isEqualTo("line one\nline two")
    }

    @Test
    fun hardLineBreakViaTrailingSpacesBecomesNewline() {
        val spanned = onlyText("line one  \nline two")
        assertThat(spanned.toString()).isEqualTo("line one\nline two")
    }

    @Test
    fun link() {
        val spanned = onlyText("[example](https://example.com)")
        assertThat(spanned.toString()).isEqualTo("example")
        val spans = spanned.getSpans(0, spanned.length, ClickableSpan::class.java)
        assertThat(spans).hasLength(1)

        var clickedUrl: String? = null
        val clickable = onlyText("[example](https://example.com)", renderer(linkHandler = { url -> clickedUrl = url; true }))
        val span = clickable.getSpans(0, clickable.length, ClickableSpan::class.java).first()
        span.onClick(android.view.View(context))
        assertThat(clickedUrl).isEqualTo("https://example.com")
    }

    @Test
    fun autolink() {
        val spanned = onlyText("<https://example.com/auto>")
        assertThat(spanned.toString()).isEqualTo("https://example.com/auto")
        assertThat(spanned.getSpans(0, spanned.length, ClickableSpan::class.java)).hasLength(1)
    }

    @Test
    fun referenceStyleLink() {
        val markdown = "[example][ref]\n\n[ref]: https://example.com/reffed\n"
        val spanned = onlyText(markdown)
        assertThat(spanned.toString()).isEqualTo("example")
        assertThat(spanned.getSpans(0, spanned.length, ClickableSpan::class.java)).hasLength(1)
    }

    @Test
    fun escapedCharactersRenderAsLiteralText() {
        val spanned = onlyText("\\*not italic\\*")
        assertThat(spanned.toString()).isEqualTo("*not italic*")
        assertThat(spanned.getSpans(0, spanned.length, StyleSpan::class.java)).isEmpty()
    }

    @Test
    fun blockQuote() {
        val spanned = onlyText("> quoted text")
        assertThat(spanned.toString()).isEqualTo("quoted text")
        assertThat(spanned.getSpans(0, spanned.length, ThemedQuoteSpan::class.java)).isNotEmpty()
    }

    @Test
    fun nestedBlockQuoteHasTwoStackedBars() {
        val spanned = onlyText("> outer\n> > inner")
        val innerStart = spanned.indexOf("inner")
        val bars = spanned.getSpans(innerStart, innerStart + 1, ThemedQuoteSpan::class.java)
        assertThat(bars.size).isEqualTo(2)
        val outerOnlyStart = spanned.indexOf("outer")
        val outerBars = spanned.getSpans(outerOnlyStart, outerOnlyStart + 1, ThemedQuoteSpan::class.java)
        assertThat(outerBars.size).isEqualTo(1)
    }

    @Test
    fun thematicBreak() {
        val spanned = onlyText("above\n\n---\n\nbelow")
        assertThat(spanned.toString()).contains("above")
        assertThat(spanned.toString()).contains("below")
    }

    @Test
    fun unorderedListItem() {
        val spanned = onlyText("- item one")
        assertThat(spanned.toString()).isEqualTo("item one")
        assertThat(spanned.getSpans(0, spanned.length, BulletSpan::class.java)).isNotEmpty()
    }

    @Test
    fun orderedListWithNonOneStartNumber() {
        val spanned = onlyText("5. fifth\n6. sixth")
        assertThat(spanned.toString()).isEqualTo("fifth\nsixth")
        assertThat(spanned.getSpans(0, spanned.length, OrderedListItemSpan::class.java)).isNotEmpty()
    }

    @Test
    fun nestedList() {
        val spanned = onlyText("- outer\n  - inner")
        assertThat(spanned.toString()).isEqualTo("outer\ninner")
        val innerStart = spanned.indexOf("inner")
        val outerStart = spanned.indexOf("outer")
        val innerMargins = spanned.getSpans(innerStart, innerStart + 1, android.text.style.LeadingMarginSpan::class.java)
        val outerMargins = spanned.getSpans(outerStart, outerStart + 1, android.text.style.LeadingMarginSpan::class.java)
        val innerIndent = innerMargins.sumOf { it.getLeadingMargin(true) }
        val outerIndent = outerMargins.sumOf { it.getLeadingMargin(true) }
        assertThat(innerIndent).isGreaterThan(outerIndent)
    }

    @Test
    fun taskListCheckedAndUnchecked() {
        val spanned = onlyText("- [x] done\n- [ ] not done")
        assertThat(spanned.toString()).isEqualTo("done\nnot done")
        val spans = spanned.getSpans(0, spanned.length, TaskListItemSpan::class.java)
        assertThat(spans).hasLength(2)
    }

    @Test
    fun image_createsAsyncImageSpanWithAltTextAndUrl() {
        val spanned = onlyText("![alt text](https://example.com/pic.png)")
        val spans = spanned.getSpans(0, spanned.length, AsyncImageSpan::class.java)
        assertThat(spans).hasLength(1)
        assertThat(spans[0].altText).isEqualTo("alt text")
        assertThat(spans[0].url).isEqualTo("https://example.com/pic.png")
    }

    @Test
    fun htmlBlockRendersAsInertLiteralText() {
        val spanned = onlyText("<script>alert('x')</script>")
        assertThat(spanned.toString()).contains("<script>")
        assertThat(spanned.toString()).contains("</script>")
    }

    @Test
    fun htmlInlineRendersAsInertLiteralText() {
        val spanned = onlyText("before <b>raw</b> after")
        assertThat(spanned.toString()).isEqualTo("before <b>raw</b> after")
    }

    @Test
    fun table_becomesADedicatedSegmentWithAlignment() {
        val markdown = """
            | Left | Center | Right |
            | :-- | :-: | --: |
            | a | b | c |
        """.trimIndent()
        val segments = renderer().render(markdown, theme, bounds)
        val table = segments.filterIsInstance<RenderedSegment.TableSegment>().single().table
        assertThat(table.columnAlignments).containsExactly(
            THKTableAlignment.START, THKTableAlignment.CENTER, THKTableAlignment.END
        ).inOrder()
        assertThat(table.headerRow.map { it.toString() }).containsExactly("Left", "Center", "Right").inOrder()
        assertThat(table.bodyRows).hasSize(1)
        assertThat(table.bodyRows[0].map { it.toString() }).containsExactly("a", "b", "c").inOrder()
    }

    @Test
    fun table_cellContentSupportsInlineMarkdown() {
        val markdown = "| h |\n| --- |\n| **bold** and [a link](https://example.com) |\n"
        val segments = renderer().render(markdown, theme, bounds)
        val table = segments.filterIsInstance<RenderedSegment.TableSegment>().single().table
        val cell = table.bodyRows[0][0] as Spannable
        assertThat(cell.toString()).isEqualTo("bold and a link")
        assertThat(cell.getSpans(0, cell.length, StyleSpan::class.java).any { it.style == android.graphics.Typeface.BOLD }).isTrue()
        assertThat(cell.getSpans(0, cell.length, ClickableSpan::class.java)).isNotEmpty()
    }

    @Test
    fun textBeforeAndAfterATableAreSeparateSegments() {
        val markdown = "before\n\n| a |\n| --- |\n| 1 |\n\nafter"
        val segments = textSegments(markdown, renderer())
        val all = renderer().render(markdown, theme, bounds)
        assertThat(all).hasSize(3)
        assertThat((all[0] as RenderedSegment.TextSegment).spanned.toString()).isEqualTo("before")
        assertThat(all[1]).isInstanceOf(RenderedSegment.TableSegment::class.java)
        assertThat((all[2] as RenderedSegment.TextSegment).spanned.toString()).isEqualTo("after")
        assertThat(segments).hasSize(2)
    }

    @Test
    fun mostMessagesWithoutATableRenderAsExactlyOneSegment() {
        val markdown = "# Title\n\nSome *text* with a [link](https://example.com) and a list:\n\n- one\n- two"
        val segments = renderer().render(markdown, theme, bounds)
        assertThat(segments).hasSize(1)
        assertThat(segments[0]).isInstanceOf(RenderedSegment.TextSegment::class.java)
    }

    @Test
    fun codeBlock_getsACopyableBlockWithTheCodeContent() {
        val text = onlyText("```kotlin\nfun main() {}\n```")
        val segments = renderer().render("```kotlin\nfun main() {}\n```", theme, bounds)
        val textSegment = segments.single() as RenderedSegment.TextSegment
        assertThat(textSegment.copyableBlocks).hasSize(1)
        val block = textSegment.copyableBlocks.single()
        assertThat(block.text).isEqualTo("fun main() {}")
        assertThat(text.subSequence(block.range.first, block.range.last + 1).toString())
            .isEqualTo("fun main() {}")
    }

    @Test
    fun outermostBlockQuote_getsACopyableBlockWithItsPlainText() {
        val markdown = "> quoted text"
        val segments = renderer().render(markdown, theme, bounds)
        val textSegment = segments.single() as RenderedSegment.TextSegment
        assertThat(textSegment.copyableBlocks).hasSize(1)
        assertThat(textSegment.copyableBlocks.single().text).isEqualTo("quoted text")
    }

    @Test
    fun nestedBlockQuote_onlyTheOutermostGetsACopyableBlock() {
        val markdown = "> outer\n> > inner"
        val segments = renderer().render(markdown, theme, bounds)
        val textSegment = segments.single() as RenderedSegment.TextSegment
        // Only one CopyableBlock for the whole (outermost) quote, matching the existing
        // "only the outermost quote gets the rounded background" rule - not one per level.
        assertThat(textSegment.copyableBlocks).hasSize(1)
        assertThat(textSegment.copyableBlocks.single().text).isEqualTo("outer\ninner")
    }

    @Test
    fun mermaidFencedBlock_becomesADiagramSegmentNotACodeBlock() {
        val markdown = "before\n\n```mermaid\nflowchart LR\n    A --> B\n```\n\nafter"
        val segments = renderer().render(markdown, theme, bounds)
        val diagramSegments = segments.filterIsInstance<RenderedSegment.DiagramSegment>()
        assertThat(diagramSegments).hasSize(1)
        assertThat(diagramSegments.single().mermaidSource).isEqualTo("flowchart LR\n    A --> B")

        // Surrounding text is split into its own segments, same as around a table, and
        // no TextSegment anywhere contains the mermaid source as a rendered code block.
        val textSegments = segments.filterIsInstance<RenderedSegment.TextSegment>()
        assertThat(textSegments.map { it.spanned.toString() }).containsExactly("before", "after").inOrder()
        assertThat(textSegments.none { it.spanned.toString().contains("flowchart") }).isTrue()
    }

    @Test
    fun mermaidLanguageTagIsCaseInsensitive() {
        val segments = renderer().render("```Mermaid\nflowchart TD\n    A --> B\n```", theme, bounds)
        assertThat(segments.single()).isInstanceOf(RenderedSegment.DiagramSegment::class.java)
    }
}
