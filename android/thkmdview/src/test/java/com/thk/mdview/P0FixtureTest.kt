package com.thk.mdview

import android.os.Handler
import android.os.Looper
import android.text.Spanned
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

@RunWith(AndroidJUnit4::class)
class P0FixtureTest {
    @Test fun p0LayoutMatrixAndRebinding() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val view = THKMDView(context)
        for (widthDp in listOf(180, 340, 720)) for (font in listOf(15f, 24f)) {
            view.theme = THKMDTheme.Default.copy(bodyFontSizeSp = font, codeFontSizeSp = font, bodyTextColor = 0xFF804020.toInt())
            val width = (widthDp * context.resources.displayMetrics.density).toInt()
            for (fixture in cases()) {
                view.reset()
                view.setMarkdown(fixture.getString("markdown"))
                view.measure(android.view.View.MeasureSpec.makeMeasureSpec(width, android.view.View.MeasureSpec.EXACTLY),
                    android.view.View.MeasureSpec.makeMeasureSpec(0, android.view.View.MeasureSpec.UNSPECIFIED))
                view.layout(0, 0, width, view.measuredHeight)
                assertTrue(view.measuredHeight > 0)
                view.appendMarkdownChunk("旧片段")
                view.reset()
                view.setMarkdown("新消息")
                shadowOf(Looper.getMainLooper()).runToEndOfTasks()
                assertEquals("新消息", (view.getChildAt(0) as TextSegmentFrame).textView.text.toString())
            }
        }
    }
    @Test fun emptyStreamingFenceDoesNotInvalidateEnclosingQuoteCopyRange() {
        val text = (render("> 引用说明。\n>\n> ```swift\n").first() as RenderedSegment.TextSegment)
        assertTrue(text.copyableBlocks.isNotEmpty())
        for (block in text.copyableBlocks) {
            assertTrue(block.range.last < text.spanned.length)
            assertEquals(block.text, text.spanned.subSequence(block.range.first, block.range.last + 1).toString())
        }
    }
    @Test fun nestedTableFallbackKeepsHeaderBoldWithoutBoldingBody() {
        for (id in listOf("P0-12", "P0-13")) {
            val fixture = cases().single { it.getString("id") == id }
            val text = (render(fixture.getString("markdown")).first() as RenderedSegment.TextSegment).spanned as Spanned
            for (label in listOf("名称", "值")) {
                val offset = text.toString().indexOf(label)
                assertTrue(text.getSpans(offset, offset + label.length, android.text.style.StyleSpan::class.java)
                    .any { it.style == android.graphics.Typeface.BOLD })
            }
            val body = text.toString().indexOf(if (id == "P0-12") "alpha" else "beta")
            assertFalse(text.getSpans(body, body + 1, android.text.style.StyleSpan::class.java)
                .any { it.style == android.graphics.Typeface.BOLD })
        }
    }
    @Test fun nestedListMarginsDoNotAccumulateAncestorMarkers() {
        val text = (render("- 一级\n  - 二级\n    - 三级\n- 返回一级").first() as RenderedSegment.TextSegment).spanned as Spanned
        val density = ApplicationProvider.getApplicationContext<android.content.Context>().resources.displayMetrics.density
        val margins = listOf("一级", "二级", "三级", "返回一级").map { label ->
            val start = text.toString().indexOf(label)
            val spans = text.getSpans(start, start + 1, android.text.style.LeadingMarginSpan::class.java)
            assertEquals(1, spans.count { it is android.text.style.BulletSpan })
            spans.sumOf { it.getLeadingMargin(true) }
        }
        assertEquals((20 * density).toInt(), margins[1] - margins[0])
        assertEquals((20 * density).toInt(), margins[2] - margins[1])
        assertEquals(margins[0], margins[3])
    }
    @Test fun nestedCopyButtonsUseParentFirstOrderWithoutChangingPayloads() {
        val frame = TextSegmentFrame(ApplicationProvider.getApplicationContext())
        val copied = mutableListOf<String>()
        frame.updateCopyButtons(
            listOf(CopyableBlock(5..9, "code"), CopyableBlock(0..14, "quote")),
            THKMDTheme.Default, { copied.add(it) }
        )
        frame.getChildAt(1).performClick()
        frame.getChildAt(2).performClick()
        assertEquals(listOf("quote", "code"), copied)
    }

    @Test fun nestedQuoteBarsEndAtTextRatherThanSharedBottomPadding() {
        val second = ThemedQuoteSpan(barColor = 0, nestedBottomPaddingPx = 10)
        val third = ThemedQuoteSpan(barColor = 0)
        // Last line baseline 40, font descent 4, and 10px of level-2 padding.
        assertEquals(44, second.barBottomForLine(40, 54, 4, true))
        assertEquals(44, third.barBottomForLine(40, 54, 4, true))
        // A non-final line stays continuous into the next line.
        assertEquals(54, second.barBottomForLine(40, 54, 4, false))
        // The containing outer bar still spans the nested block's blank space.
        val outer = ThemedQuoteSpan(barColor = 0, backgroundColor = 0, barVerticalInsetPx = 3)
        assertEquals(51, outer.barBottomForLine(40, 54, 4, true))
    }

    @Test fun secondLevelBottomPaddingOnlyAppliesToLastLine() {
        val span = ThemedQuoteSpan(
            barColor = 0, spanStart = 0, spanEnd = 5,
            nestedTopPaddingPx = 10, nestedBottomPaddingPx = 10
        )
        fun metrics() = android.graphics.Paint.FontMetricsInt().apply {
            top = -18; ascent = -16; descent = 4; bottom = 6
        }
        val first = metrics()
        span.chooseHeight("ab\ncd", 0, 3, 0, 0, first)
        assertEquals(-26, first.ascent)
        assertEquals(4, first.descent)
        val last = metrics()
        span.chooseHeight("ab\ncd", 3, 5, 0, 20, last)
        assertEquals(-16, last.ascent)
        assertEquals(14, last.descent)
        // A repeated layout pass must not keep adding the bottom gap.
        span.chooseHeight("ab\ncd", 3, 5, 0, 20, last)
        assertEquals(14, last.descent)
    }

    private val renderer = DefaultMarkdownRenderer(ApplicationProvider.getApplicationContext())
    private fun render(markdown: String) = renderer.render(markdown, THKMDTheme.Default, ImageBounds(240, 320))
    private fun cases(): List<JSONObject> {
        val stream = requireNotNull(javaClass.classLoader!!.getResourceAsStream("p0.json"))
        val catalog = JSONObject(stream.bufferedReader().use { it.readText() })
        assertEquals(1, catalog.getInt("schemaVersion"))
        val values = catalog.getJSONArray("cases")
        return (0 until values.length()).map { values.getJSONObject(it) }
    }

    private fun fingerprint(segments: List<RenderedSegment>): List<String> = segments.map {
        when (it) {
            is RenderedSegment.TextSegment -> "text:${it.spanned}"
            is RenderedSegment.TableSegment -> "table:" + (listOf(it.table.headerRow) + it.table.bodyRows)
                .joinToString("\n") { row -> row.joinToString(" | ") }
            is RenderedSegment.DiagramSegment -> "diagram:${it.mermaidSource}"
        }
    }

    @Test fun allSharedCasesRenderEveryPrefixAndMatchTheirContracts() {
        val fixtures = cases()
        assertEquals(18, fixtures.size)
        assertEquals(fixtures.size, fixtures.map { it.getString("id") }.distinct().size)
        for (fixture in fixtures) {
            val id = fixture.getString("id")
            val chunks = fixture.getJSONArray("chunks")
            var prefix = ""
            var latest: List<RenderedSegment> = emptyList()
            var renderCount = 0
            val buffer = StreamingMarkdownBuffer(32L, Handler(Looper.getMainLooper())) {
                renderCount++
                latest = render(it)
            }
            for (index in 0 until chunks.length()) {
                val chunk = chunks.getString(index)
                prefix += chunk
                buffer.append(chunk)
                // Flush EACH chunk: this exercises transient states, not just the final buffer.
                shadowOf(Looper.getMainLooper()).runToEndOfTasks()
                assertEquals("$id prefix $index", fingerprint(render(prefix)), fingerprint(latest))
                val checkpoints = fixture.getJSONArray("checkpoints")
                for (checkpointIndex in 0 until checkpoints.length()) {
                    val checkpoint = checkpoints.getJSONObject(checkpointIndex)
                    if (checkpoint.getInt("afterChunk") != index + 1) continue
                    assertEquals(id, checkpoint.getInt("tableCount"), latest.count { it is RenderedSegment.TableSegment })
                    assertEquals(id, checkpoint.getInt("diagramCount"), latest.count { it is RenderedSegment.DiagramSegment })
                    val fragments = checkpoint.getJSONArray("textContains")
                    for (i in 0 until fragments.length()) {
                        assertTrue("$id checkpoint", fingerprint(latest).joinToString("\n").contains(fragments.getString(i)))
                    }
                }
                latest.filterIsInstance<RenderedSegment.TextSegment>().forEach { segment ->
                    segment.copyableBlocks.forEach { block ->
                        assertTrue("$id copy range", block.range.first >= 0 && block.range.last < segment.spanned.length)
                        assertEquals(block.text, segment.spanned.subSequence(block.range.first, block.range.last + 1).toString())
                    }
                }
            }
            assertEquals("$id rendered each chunk", chunks.length(), renderCount)
            assertEquals(id, fixture.getString("markdown"), prefix)
            val expected = fixture.getJSONObject("expected")
            assertEquals(id, expected.getInt("tableCount"), latest.count { it is RenderedSegment.TableSegment })
            assertEquals(id, expected.getInt("diagramCount"), latest.count { it is RenderedSegment.DiagramSegment })
            val plain = fingerprint(latest).joinToString("\n")
            val fragments = expected.getJSONArray("textContains")
            for (i in 0 until fragments.length()) assertTrue("$id missing ${fragments.getString(i)}", plain.contains(fragments.getString(i)))
            val copies = latest.filterIsInstance<RenderedSegment.TextSegment>().flatMap { it.copyableBlocks }.map { it.text }
            val expectedCopies = expected.getJSONArray("copyTexts")
            for (i in 0 until expectedCopies.length()) assertTrue("$id copy text", copies.contains(expectedCopies.getString(i)))
            buffer.reset()
        }
    }

    @Test fun nestedCodeAndQuoteReserveSideGutters() {
        for (fixture in cases().filter { it.getString("id") in listOf("P0-05", "P0-06", "P0-09") }) {
            val texts = render(fixture.getString("markdown")).filterIsInstance<RenderedSegment.TextSegment>()
            val spans = texts.map { it.spanned as Spanned }
            assertTrue(spans.any { text ->
                text.getSpans(0, text.length, CodeBlockBackgroundSpan::class.java).any { it.copyButtonGutterPx > 0 } ||
                    text.getSpans(0, text.length, ThemedQuoteSpan::class.java).any { it.copyButtonGutterPx > 0 }
            })
        }
    }

    @Test fun switchingFixtureCancelsPendingRender() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.appendMarkdownChunk(cases().first().getString("markdown"))
        view.reset()
        view.setMarkdown("新的用例")
        shadowOf(Looper.getMainLooper()).runToEndOfTasks()
        val frame = view.getChildAt(0) as TextSegmentFrame
        assertEquals("新的用例", frame.textView.text.toString())
    }
}
