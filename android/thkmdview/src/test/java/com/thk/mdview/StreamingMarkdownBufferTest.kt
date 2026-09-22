package com.thk.mdview

import android.os.Handler
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import kotlin.random.Random

private val TEST_IMAGE_BOUNDS = ImageBounds(800, 600)

private fun DefaultMarkdownRenderer.renderText(markdown: String): String =
    render(markdown, THKMDTheme.Default, TEST_IMAGE_BOUNDS).joinToString("") { segment ->
        when (segment) {
            is RenderedSegment.TextSegment -> segment.spanned.toString()
            is RenderedSegment.TableSegment -> "[table]"
        }
    }

@RunWith(AndroidJUnit4::class)
class StreamingMarkdownBufferTest {

    private val fixture = """
        # Streaming Fixture

        This is **bold**, this is *italic*, and here is a [link](https://example.com/path).

        - first item
        - second item
        - third item

        > a blockquote spanning
        > two lines

        ```
        fun greet(name: String) {
            println("hello, ${'$'}name")
        }
        ```
    """.trimIndent()

    private fun chunksFixedSize(text: String, size: Int): List<String> =
        text.chunked(size)

    private fun chunksRandomSize(text: String, seed: Long): List<String> {
        val random = Random(seed)
        val chunks = mutableListOf<String>()
        var i = 0
        while (i < text.length) {
            val size = random.nextInt(1, 12)
            val end = minOf(i + size, text.length)
            chunks.add(text.substring(i, end))
            i = end
        }
        return chunks
    }

    private fun chunksOneCharAtATime(text: String): List<String> = text.map { it.toString() }

    @Test
    fun chunkedStreaming_matchesSingleSetMarkdownRegardlessOfBoundaries() {
        val renderer = DefaultMarkdownRenderer(ApplicationProvider.getApplicationContext())
        val expected = renderer.renderText(fixture)

        val strategies: List<Pair<String, List<String>>> = listOf(
            "fixedSize-7" to chunksFixedSize(fixture, 7),
            "fixedSize-23" to chunksFixedSize(fixture, 23),
            "randomSize-seed1" to chunksRandomSize(fixture, seed = 1L),
            "randomSize-seed42" to chunksRandomSize(fixture, seed = 42L),
            "oneCharAtATime" to chunksOneCharAtATime(fixture)
        )

        for ((name, chunks) in strategies) {
            var lastRendered: String? = null
            val handler = Handler(Looper.getMainLooper())
            val buffer = StreamingMarkdownBuffer(debounceMs = 32L, handler = handler) { markdown ->
                lastRendered = renderer.renderText(markdown)
            }

            for (chunk in chunks) {
                buffer.append(chunk)
            }
            shadowOf(Looper.getMainLooper()).runToEndOfTasks()

            assertThat(buffer.currentText).isEqualTo(fixture)
            if (lastRendered != expected) {
                throw AssertionError("Strategy '$name' produced a mismatched render")
            }
        }
    }

    @Test
    fun rapidAppends_withinOneDebounceWindow_coalesceIntoASingleRenderPass() {
        var renderCount = 0
        var lastText: String? = null
        val handler = Handler(Looper.getMainLooper())
        val buffer = StreamingMarkdownBuffer(debounceMs = 32L, handler = handler) { markdown ->
            renderCount++
            lastText = markdown
        }

        repeat(25) { i ->
            buffer.append("chunk$i ")
        }

        // Nothing has run yet: all renders were debounced and coalesced.
        assertThat(renderCount).isEqualTo(0)

        shadowOf(Looper.getMainLooper()).runToEndOfTasks()

        assertThat(renderCount).isEqualTo(1)
        assertThat(lastText).isEqualTo((0 until 25).joinToString("") { "chunk$it " })
    }

    @Test
    fun reset_cancelsPendingRenderAndClearsBuffer() {
        var renderCount = 0
        val handler = Handler(Looper.getMainLooper())
        val buffer = StreamingMarkdownBuffer(debounceMs = 32L, handler = handler) {
            renderCount++
        }

        buffer.append("some in-flight text")
        buffer.reset()

        shadowOf(Looper.getMainLooper()).runToEndOfTasks()

        assertThat(renderCount).isEqualTo(0)
        assertThat(buffer.currentText).isEmpty()
    }
}
