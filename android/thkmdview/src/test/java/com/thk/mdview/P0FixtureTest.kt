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
