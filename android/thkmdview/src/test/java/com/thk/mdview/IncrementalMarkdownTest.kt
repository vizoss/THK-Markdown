package com.thk.mdview

import android.text.Spanned
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class IncrementalMarkdownTest {
    private fun renderer() = DefaultMarkdownRenderer(ApplicationProvider.getApplicationContext())
    private val stable = "# 前文\n\n- 已完成\n  - 嵌套\n\n> 引用结束\n\n---\n\n"

    // Compare segment boundaries, table cells/alignment, copy ranges and all span
    // ranges/types plus scalar styling fields; ignore callback/object identities.
    private fun text(value: CharSequence): String {
        val spans = (value as? Spanned)?.let { s ->
            s.getSpans(0, s.length, Any::class.java).map { span ->
                val fields = generateSequence(span.javaClass as Class<*>?) { it.superclass }
                    .flatMap { it.declaredFields.asSequence() }
                    .filter { !java.lang.reflect.Modifier.isStatic(it.modifiers) && it.name != "mId" }
                    .mapNotNull { field ->
                        field.isAccessible = true
                        val v = field.get(span)
                        if (v is Number || v is Boolean || v is String || v is Enum<*>) "${field.name}=$v" else null
                    }.sorted().joinToString()
                "${span.javaClass.name}:${s.getSpanStart(span)}:${s.getSpanEnd(span)}:${s.getSpanFlags(span)}:$fields"
            }.sorted()
        }
        return "$value|$spans"
    }
    private fun signature(renderer: DefaultMarkdownRenderer, source: String): List<String> =
        renderer.render(source, THKMDTheme.Default, ImageBounds(240, 320)).map {
            when (it) {
                is RenderedSegment.TextSegment -> "text:${text(it.spanned)}:${it.copyableBlocks}"
                is RenderedSegment.TableSegment -> "table:${it.table.columnAlignments}:${it.table.headerRow.map(::text)}:${it.table.bodyRows.map { row -> row.map(::text) }}"
                is RenderedSegment.DiagramSegment -> "diagram:${it.mermaidSource}"
            }
        }

    @Test fun catalogsMatchFullParsingAtEveryRecordedChunk() {
        for (catalog in listOf("p0", "p1", "p2", "p3")) {
            val json = javaClass.classLoader!!.getResourceAsStream("$catalog.json")!!.bufferedReader().use { it.readText() }
            val cases = JSONObject(json).getJSONArray("cases")
            for (i in 0 until cases.length()) {
                val fixture = cases.getJSONObject(i)
                val incremental = renderer()
                val full = renderer().apply { incrementalParsingEnabled = false }
                var source = stable
                signature(incremental, source)
                val chunks = fixture.getJSONArray("chunks")
                for (j in 0 until chunks.length()) {
                    source += chunks.getString(j)
                    assertEquals("${fixture.getString("id")} chunk $j", signature(full, source), signature(incremental, source))
                }
                // Non-append edits, truncation and reset must invalidate cached blocks.
                for (edited in listOf(source.replace("前文", "修改"), source.take(source.length / 2), "短文")) {
                    assertEquals(signature(full, edited), signature(incremental, edited))
                }
                incremental.clearIncrementalState()
                assertEquals(signature(full, source), signature(incremental, source))
            }
        }
    }

    @Test fun ambiguousBoundariesMatchAtEveryCharacter() {
        val sources = listOf(
            "- one\n\n- two\n\n  continuation\n\n- three",
            "> quote\n>\n> - item\n>   continuation\n\nend",
            "a | b\n--- | ---\n1 | **two**\n\nend",
            "```text\na\n\nb\n```\n\nend",
            "~~~mermaid\ngraph LR\nA-->B\n~~~\n\nend",
            "title\n---\n\n    indented\n\n    code\n\nend",
            "<div>\n\ntext\n</div>\n\nend",
            "<!-- open\n\ncomment -->\n\nend",
            "[a\\]b]\n\n[a\\]b]: /target\n\nend",
            "[a\nb]\n\n[a\nb]: /target\n\nend",
            "$$\na\n\nb\n$$\n\nend",
            "`a\n\nb`\n\nend",
            "one[^a]\n\n[^a]: footnote\n\nend",
            "- a\r\n\r\n- b\r\n\r\nend"
        )
        for (suffix in sources) {
            val incremental = renderer()
            val full = renderer().apply { incrementalParsingEnabled = false }
            signature(incremental, stable)
            for (end in 1..suffix.length) {
                val source = stable + suffix.take(end)
                assertEquals(source, signature(full, source), signature(incremental, source))
            }
        }
    }

    @Test fun complexBlocksAreActuallyReusedAndDefinitionsInvalidateThem() {
        val incremental = renderer()
        val source = stable.repeat(20) + "```\nactive"
        signature(incremental, source)
        signature(incremental, "$source more")
        assertTrue(incremental.lastParsedCharacters < 100)
        val definition = "$source more\n```\n\n[ref]: /url"
        signature(incremental, definition)
        assertEquals(MarkdownExtensions.prepare(definition).length, incremental.lastParsedCharacters)
    }

    @Test fun deterministicMixedBlocksMatchAcrossChunkSizes() {
        val random = kotlin.random.Random(924)
        val blocks = listOf("paragraph **bold**", "- a\n- b", "> quote\n>\n> nested",
            "```\ncode\n```", "a | b\n--- | ---\n1 | 2", "---", "## heading",
            "    indented", "[link](https://example.com)", "<div>\nhtml\n</div>", "\$x\$")
        repeat(40) {
            val source = (0..9).joinToString("\n\n") { blocks[random.nextInt(blocks.size)] }
            val incremental = renderer()
            val full = renderer().apply { incrementalParsingEnabled = false }
            var end = 0
            while (end < source.length) {
                end = (end + random.nextInt(1, 13)).coerceAtMost(source.length)
                val prefix = source.take(end)
                assertEquals(prefix, signature(full, prefix), signature(incremental, prefix))
            }
        }
    }
}
