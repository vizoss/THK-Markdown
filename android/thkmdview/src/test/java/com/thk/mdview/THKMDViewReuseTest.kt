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

    private class RecordingRenderer : MarkdownRenderer {
        var callCount = 0
        val renderedInputs = mutableListOf<String>()

        override fun render(markdown: String): CharSequence {
            callCount++
            renderedInputs.add(markdown)
            return markdown
        }
    }

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
        assertThat(view.text.toString()).isEmpty()

        // The recycled view is immediately rebound to a different message.
        view.setMarkdown("message B, a totally different message")

        // setMarkdown renders synchronously, with no debounce.
        assertThat(view.text.toString()).isEqualTo("message B, a totally different message")

        // Flush the looper: if reset() had failed to cancel the pending Runnable from
        // "message A", it would fire here and clobber message B's text.
        shadowOf(Looper.getMainLooper()).runToEndOfTasks()

        assertThat(view.text.toString()).isEqualTo("message B, a totally different message")
        assertThat(renderer.renderedInputs).doesNotContain("message A, still streaming...")
    }

    @Test
    fun reset_isSafeToCallWithNoPendingWork() {
        val view = THKMDView(ApplicationProvider.getApplicationContext())
        view.reset()
        view.reset()
        assertThat(view.text.toString()).isEmpty()
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
        assertThat(view.text.toString()).isEqualTo("Hello, world!")
    }
}
