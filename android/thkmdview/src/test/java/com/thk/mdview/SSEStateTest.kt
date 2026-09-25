package com.thk.mdview

import android.app.Activity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

@RunWith(AndroidJUnit4::class)
class SSEStateTest {
    @Test fun sharedReplyCatalogHasThirtyCompleteDistinctStreamableReplies() {
        val json = javaClass.classLoader!!.getResourceAsStream("replies.json")!!.bufferedReader().use { it.readText() }
        val rows = org.json.JSONArray(json)
        assertEquals(30, rows.length())
        val ids = mutableSetOf<String>()
        val renderer = DefaultMarkdownRenderer(ApplicationProvider.getApplicationContext())
        repeat(rows.length()) { i ->
            val row = rows.getJSONObject(i)
            assertTrue(ids.add(row.getString("id")))
            val chunks = row.getJSONArray("chunks")
            var source = ""
            repeat(chunks.length()) { j ->
                source += chunks.getString(j)
                renderer.render(source, THKMDTheme.Default, ImageBounds(240, 320))
            }
            assertEquals(row.getString("markdown"), source)
            assertTrue(source.length > 350)
        }
    }
    private fun view() = THKMDView(ApplicationProvider.getApplicationContext())
    private fun text(view: THKMDView) = (0 until view.childCount).mapNotNull { view.getChildAt(it) as? TextSegmentFrame }
        .joinToString("|") { it.textView.text.toString() }

    @Test fun statesFlushTailAndDoNotEnterCopiedMarkdown() {
        val view = view()
        view.sseEnabled = true
        view.setSSEState(THKSSEState.WAITING)
        assertEquals(1, view.childCount)
        view.appendMarkdownChunk("**hello**")
        assertEquals(THKSSEState.STREAMING, view.sseState)
        view.setSSEState(THKSSEState.COMPLETED)
        assertEquals("hello", text(view))
        assertTrue((0 until view.childCount).map { view.getChildAt(it) }.filterIsInstance<SSEFooter>().none { it.visibility == View.VISIBLE })
        view.reset()
        assertEquals(THKSSEState.IDLE, view.sseState)
        assertEquals(0, view.childCount)
    }

    @Test fun customIndicatorStopsOnReplacementDetachAndReset() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().visible()
        try {
            val host = FrameLayout(activity.get())
            activity.get().setContentView(host)
            val view = THKMDView(activity.get())
            val first = View(activity.get())
            val second = View(activity.get())
            val events = mutableListOf<Pair<View, Boolean>>()
            view.onSSEIndicatorActivityChanged = { indicator, active -> events += indicator to active }
            view.sseIndicatorView = first
            view.sseEnabled = true
            host.addView(view)
            // Robolectric attaches the tree but leaves its synthetic window GONE.
            // Explicitly deliver the visible-window state before testing animation.
            val attachInfo = org.robolectric.util.ReflectionHelpers.getField<Any>(view, "mAttachInfo")
            org.robolectric.util.ReflectionHelpers.setField(attachInfo, "mWindowVisibility", View.VISIBLE)
            activity.get().window.decorView.dispatchWindowVisibilityChanged(View.VISIBLE)
            view.setSSEState(THKSSEState.WAITING)
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
            assertTrue("events=$events attached=${view.isAttachedToWindow} shown=${view.isShown} window=${view.windowVisibility}", events.contains(first to true))
            view.sseIndicatorView = second
            assertTrue(events.contains(first to false))
            assertTrue(events.contains(second to true))
            host.removeView(view)
            assertEquals(second to false, events.last())
            host.addView(view)
            assertEquals(second to true, events.last())
            view.reset()
            assertEquals(second to false, events.last())
        } finally { activity.pause().stop().destroy() }
    }

    @Test fun failureKeepsTextAndRetryIsBusinessCallback() {
        val view = view()
        var retries = 0
        view.sseEnabled = true; view.onRetry = { retries++ }
        view.appendMarkdownChunk("already received")
        view.setSSEState(THKSSEState.FAILED, "Connection lost")
        assertEquals("already received", text(view))
        val footer = view.getChildAt(view.childCount - 1) as SSEFooter
        (0 until footer.childCount).map { footer.getChildAt(it) }.filterIsInstance<Button>().single().performClick()
        assertEquals(1, retries)
        assertEquals(THKSSEState.FAILED, view.sseState)
        view.sseStatusUIEnabled = false
        assertEquals(View.GONE, footer.visibility)
    }

    @Test fun incrementalFailureRetriesFullAndDoubleFailureFallsBackThenRecovers() {
        val view = view()
        var failFull = false
        var failIncremental = true
        var fullCalls = 0
        val failures = mutableListOf<THKRenderFailureStage>()
        view.onRenderFailure = { failures += it.stage }
        view.setMarkdownRenderer(object : MarkdownRenderer {
            override fun render(markdown: String, theme: THKMDTheme, imageBounds: ImageBounds): List<RenderedSegment> {
                if (failIncremental) error("incremental failed")
                return listOf(RenderedSegment.TextSegment("recovered"))
            }
            override fun renderFull(markdown: String, theme: THKMDTheme, imageBounds: ImageBounds): List<RenderedSegment> {
                fullCalls++
                if (failFull) error("full failed")
                return listOf(RenderedSegment.TextSegment("full result"))
            }
        })
        failures.clear(); fullCalls = 0
        view.sseEnabled = true; view.setSSEState(THKSSEState.STREAMING)
        view.setMarkdown("**raw**")
        assertEquals("full result", text(view)); assertEquals(1, fullCalls)
        assertEquals(listOf(THKRenderFailureStage.INCREMENTAL), failures)
        failFull = true; failures.clear()
        view.setMarkdown("**raw**")
        assertEquals("**raw**", text(view))
        assertEquals(listOf(THKRenderFailureStage.INCREMENTAL, THKRenderFailureStage.FULL), failures)
        assertEquals(THKSSEState.STREAMING, view.sseState)
        failIncremental = false
        view.setMarkdown("**raw** more")
        assertEquals("recovered", text(view))
    }

    @Test fun footerSurvivesChangingSegmentCounts() {
        val view = view()
        view.sseEnabled = true; view.setSSEState(THKSSEState.STREAMING)
        for (source in listOf("text", "a | b\n--- | ---\n1 | 2\n\nend", "", "> quote\n\nend")) {
            view.setMarkdown(source)
            assertTrue(view.getChildAt(view.childCount - 1) is SSEFooter)
            assertEquals(1, (0 until view.childCount).count { view.getChildAt(it) is SSEFooter })
        }
    }
}
