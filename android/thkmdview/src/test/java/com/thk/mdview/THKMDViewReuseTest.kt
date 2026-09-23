package com.thk.mdview

import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

@RunWith(AndroidJUnit4::class)
class THKMDViewReuseTest {
    @Test fun ordinaryParagraphAppendPreservesEditableBuffer() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.setMarkdown("第一段。\n\n第二段")
        val text = (view.getChildAt(0) as TextSegmentFrame).textView
        val buffer = text.text
        view.appendMarkdownChunk("增加文字🙂")
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1))
        assertThat(text.text).isSameInstanceAs(buffer)
        assertThat(text.text.toString()).isEqualTo("第一段。\n\n第二段增加文字🙂")
    }

    @Test fun incrementalPlainParsingMatchesFullParsingAndFallsBackForSyntaxChanges() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val incremental = DefaultMarkdownRenderer(context)
        val full = DefaultMarkdownRenderer(context).apply { incrementalParsingEnabled = false }
        val bounds = ImageBounds(240, 320)
        val cases = listOf("中文🙂第一段。\n\n第二段 **加粗**\n\n末段", "plain\n\nparagraph\n---",
            "plain\n\n[link][ref]\n\n[ref]: https://example.com", "plain\n\n> quote\n\n- list", "plain\n\n\$x\$")
        for (source in cases) {
            for (end in 1..source.length) {
                val prefix = source.substring(0, end)
                fun render(renderer: DefaultMarkdownRenderer) = renderer.render(prefix, THKMDTheme.Default, bounds)
                    .filterIsInstance<RenderedSegment.TextSegment>().joinToString("|") { it.spanned.toString() }
                assertThat(render(incremental)).isEqualTo(render(full))
            }
        }
        val prefix = "stable paragraph\n\n".repeat(100)
        incremental.render(prefix + "tail", THKMDTheme.Default, bounds)
        incremental.render(prefix + "tail more", THKMDTheme.Default, bounds)
        assertThat(incremental.lastParsedCharacters).isEqualTo("stable paragraph\n\ntail more".length)
    }

    @Test fun temporaryDetachKeepsViewsAndResumesPendingText() {
        val controller = org.robolectric.Robolectric.buildActivity(android.app.Activity::class.java).setup().visible()
        val activity = controller.get()
        val root = android.widget.FrameLayout(activity)
        activity.setContentView(root)
        val view = THKMDView(activity)
        root.addView(view)
        view.setMarkdown("before")
        val child = view.getChildAt(0)
        root.removeView(view)
        assertThat(view.getChildAt(0)).isSameInstanceAs(child)
        view.appendMarkdownChunk(" after")
        shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1))
        assertThat(firstSegmentText(view)).isEqualTo("before")
        root.addView(view)
        assertThat(firstSegmentText(view)).isEqualTo("before after")
        view.reset()
        controller.pause().stop().destroy()
    }

    @Test fun unchangedThemeDoesNotRenderAgain() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        val renderer = RecordingRenderer()
        view.setMarkdownRenderer(renderer)
        view.setMarkdown("stable")
        val count = renderer.callCount
        view.theme = view.theme.copy()
        assertThat(renderer.callCount).isEqualTo(count)
        view.theme = view.theme.copy(bodyFontSizeSp = view.theme.bodyFontSizeSp + 1)
        assertThat(renderer.callCount).isEqualTo(count + 1)
    }

    @Test fun tableReusesIdenticalCellsButRebindsFormattingAndThemeChanges() {
        val view = THKTableView(ApplicationProvider.getApplicationContext())
        val data = THKTableData(listOf(THKTableAlignment.START), listOf("Header"), listOf(listOf("same")))
        view.setData(data, THKMDTheme.Default)
        val original = view.cellViewAt(1, 0)
        view.setData(data.copy(), THKMDTheme.Default)
        assertThat(view.cellViewAt(1, 0)).isSameInstanceAs(original)
        val bold = android.text.SpannableString("same").apply {
            setSpan(android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, length, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        view.setData(data.copy(bodyRows = listOf(listOf(bold))), THKMDTheme.Default)
        assertThat(view.cellViewAt(1, 0)).isNotSameInstanceAs(original)
        val formatted = view.cellViewAt(1, 0)
        view.setData(data, THKMDTheme.Default.copy(bodyFontSizeSp = 20f))
        assertThat(view.cellViewAt(1, 0)).isNotSameInstanceAs(formatted)
    }

    @Test fun listQuoteBackgroundIncludesTheCopyGutter() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.setMarkdown("- 外层列表\n\n  > 引用第一段。\n  > > 内层引用。\n\n- 列表结尾")
        val text = (view.getChildAt(0) as TextSegmentFrame).textView.text as android.text.Spanned
        val outer = text.getSpans(0, text.length, ThemedQuoteSpan::class.java).single { it.backgroundColor != null }
        assertThat(outer.drawsInHost).isTrue()
        assertThat(outer.containerBackground).isFalse()
        val ending = text.toString().indexOf("列表结尾")
        assertThat(text.getSpans(ending, ending + 1, ThemedQuoteSpan::class.java)).isEmpty()
    }

    @Test
    fun quotedCodeCopyButtonsStayInOneColumnWithoutOverlapping() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.setMarkdown("> 引用说明。\n>\n> ```swift\n> let value = 42\n> ```\n> 引用结束。")
        val width = (360 * view.resources.displayMetrics.density).toInt()
        view.measure(android.view.View.MeasureSpec.makeMeasureSpec(width, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(0, android.view.View.MeasureSpec.UNSPECIFIED))
        view.layout(0, 0, width, view.measuredHeight)
        val frame = view.getChildAt(0) as TextSegmentFrame
        val buttons = (0 until frame.childCount).map { frame.getChildAt(it) }.filterIsInstance<android.widget.ImageButton>()
        assertThat(buttons).hasSize(2)
        assertThat(buttons[0].left).isEqualTo(buttons[1].left)
        assertThat(buttons[1].top).isAtLeast(buttons[0].bottom)
        // Button alignment must not be achieved by inserting a tall blank header.
        val firstLineHeight = frame.textView.layout.getLineBottom(0) - frame.textView.layout.getLineTop(0)
        val reference = THKMDView(ApplicationProvider.getApplicationContext())
        reference.setMarkdown("> 引用说明。\n>\n> 引用结束。")
        reference.measure(android.view.View.MeasureSpec.makeMeasureSpec(width, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(0, android.view.View.MeasureSpec.UNSPECIFIED))
        reference.layout(0, 0, width, reference.measuredHeight)
        val naturalLayout = (reference.getChildAt(0) as TextSegmentFrame).textView.layout
        assertThat(firstLineHeight).isEqualTo(naturalLayout.getLineBottom(0) - naturalLayout.getLineTop(0))
    }

    private class RecordingRenderer : MarkdownRenderer {
        var callCount = 0
        val renderedInputs = mutableListOf<String>()

        override fun render(markdown: String, theme: THKMDTheme, imageBounds: ImageBounds): List<RenderedSegment> {
            callCount++
            renderedInputs.add(markdown)
            return listOf(RenderedSegment.TextSegment(markdown))
        }
    }

    private fun firstSegmentText(view: THKMDView): String =
        (view.getChildAt(0) as? TextSegmentFrame)?.textView?.text?.toString().orEmpty()

    @Test
    fun resetPreventsAStalePendingRenderFromLandingOnANewlyBoundMessage() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        val renderer = RecordingRenderer()
        view.setMarkdownRenderer(renderer)
        val callsAfterInstall = renderer.callCount

        // Simulate a RecyclerView cell mid-stream: a chunk arrives and a debounced
        // render is now pending, but the cell gets recycled before it fires.
        view.appendMarkdownChunk("message A, still streaming...")
        assertThat(renderer.callCount).isEqualTo(callsAfterInstall)

        view.reset()
        assertThat(view.childCount).isEqualTo(0)

        // The recycled view is immediately rebound to a different message.
        view.setMarkdown("message B, a totally different message")

        // setMarkdown renders synchronously, with no debounce.
        assertThat(firstSegmentText(view)).isEqualTo("message B, a totally different message")

        // Flush the looper: if reset() had failed to cancel the pending Runnable from
        // "message A", it would fire here and clobber message B's text.
        shadowOf(Looper.getMainLooper()).runToEndOfTasks()

        assertThat(firstSegmentText(view)).isEqualTo("message B, a totally different message")
        assertThat(renderer.renderedInputs).doesNotContain("message A, still streaming...")
    }

    @Test
    fun reset_isSafeToCallWithNoPendingWork() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.reset()
        view.reset()
        assertThat(view.childCount).isEqualTo(0)
    }

    @Test
    fun appendMarkdownChunk_debouncesAndCoalescesBeforeRendering() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        val renderer = RecordingRenderer()
        view.setMarkdownRenderer(renderer)
        val callsAfterInstall = renderer.callCount

        view.appendMarkdownChunk("Hello")
        view.appendMarkdownChunk(", ")
        view.appendMarkdownChunk("world!")

        assertThat(renderer.callCount).isEqualTo(callsAfterInstall)

        shadowOf(Looper.getMainLooper()).runToEndOfTasks()

        assertThat(renderer.callCount).isEqualTo(callsAfterInstall + 1)
        assertThat(firstSegmentText(view)).isEqualTo("Hello, world!")
    }

    @Test
    fun diagramSegment_getsItsOwnTHKMermaidViewChild_andResetTearsItDown() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.setMarkdown("```mermaid\nflowchart LR\n    A --> B\n```")
        assertThat(view.childCount).isEqualTo(1)
        assertThat(view.getChildAt(0)).isInstanceOf(THKMermaidView::class.java)

        view.reset()
        assertThat(view.childCount).isEqualTo(0)
    }

    @Test
    fun reset_removesTableSegmentsToo() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.setMarkdown("| a |\n| --- |\n| 1 |\n")
        assertThat(view.childCount).isEqualTo(1)
        assertThat(view.getChildAt(0)).isInstanceOf(THKTableView::class.java)

        view.reset()
        assertThat(view.childCount).isEqualTo(0)
    }

    @Test
    fun rebuildingSegments_reusesATextViewOfTheSameTypeInPlace() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.setMarkdown("first")
        val firstChild = view.getChildAt(0)
        assertThat(firstChild).isInstanceOf(TextSegmentFrame::class.java)

        view.setMarkdown("second, still just text")
        assertThat(view.childCount).isEqualTo(1)
        // Same child view instance reused, not torn down and recreated.
        assertThat(view.getChildAt(0)).isSameInstanceAs(firstChild)
        assertThat(firstSegmentText(view)).isEqualTo("second, still just text")
    }

    @Test
    fun changingSegmentTypeAtAnIndex_replacesRatherThanCrashes() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.setMarkdown("just text, no table")
        assertThat(view.getChildAt(0)).isInstanceOf(TextSegmentFrame::class.java)

        view.setMarkdown("| a |\n| --- |\n| 1 |\n")
        assertThat(view.childCount).isEqualTo(1)
        assertThat(view.getChildAt(0)).isInstanceOf(THKTableView::class.java)
    }

    @Test
    fun settingTheme_reRendersCurrentContentWithNewColorsWithoutAFreshSetMarkdown() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.setMarkdown("hello theme")

        val customTheme = THKMDTheme.Default.copy(bodyTextColor = 0xFF123456.toInt())
        view.theme = customTheme

        val textView = (view.getChildAt(0) as TextSegmentFrame).textView
        assertThat(textView.currentTextColor).isEqualTo(0xFF123456.toInt())
        assertThat(textView.text.toString()).isEqualTo("hello theme")
    }

    @Test
    fun imageLoad_fromARecycledAwayView_neverPaintsOntoItsReplacement() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val gate = kotlinx.coroutines.CompletableDeferred<android.graphics.Bitmap?>()
        val loader = object : THKImageLoader {
            override suspend fun load(url: String): android.graphics.Bitmap? = gate.await()
        }

        val view = THKMDView(context)
        view.imageLoader = loader
        view.setMarkdown("![alt](https://example.com/pic.png)")

        val recycledTextView = (view.getChildAt(0) as TextSegmentFrame).textView
        val span = (recycledTextView.text as android.text.Spanned)
            .getSpans(0, recycledTextView.text.length, AsyncImageSpan::class.java)
            .first()

        // Simulate RecyclerView recycling this view mid-load.
        view.reset()
        shadowOf(recycledTextView).clearWasInvalidated()

        // The load "completes" only after the view has moved on; because reset()
        // cancelled the coroutine, this resolution must never reach the old TextView.
        gate.complete(android.graphics.Bitmap.createBitmap(10, 10, android.graphics.Bitmap.Config.ARGB_8888))
        shadowOf(Looper.getMainLooper()).runToEndOfTasks()

        assertThat(shadowOf(recycledTextView).wasInvalidated()).isFalse()
        assertThat(span).isNotNull()
    }
}
