package com.thk.mdview

import android.graphics.Bitmap
import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AsyncImageSpanTest {
    @Test
    @org.robolectric.annotation.GraphicsMode(org.robolectric.annotation.GraphicsMode.Mode.NATIVE)
    fun failedImagePlaceholderRemainsVisibleAtLineAndParagraphEnds() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val color = Color.MAGENTA
        val theme = THKMDTheme.Default.copy(imagePlaceholderColor = color)
        val renderer = DefaultMarkdownRenderer(context)
        val loader = object : THKImageLoader {
            override suspend fun load(url: String): Bitmap? = null
        }
        for (source in listOf(
            "![失败图片](https://fixtures.thk.invalid/fail.png)",
            "失败之前 ![失败图片](https://fixtures.thk.invalid/fail.png)",
            "失败之前 ![失败图片](https://fixtures.thk.invalid/fail.png) 失败之后。"
        )) {
            val text = renderer.render(source, theme, ImageBounds(120, 240))
                .filterIsInstance<RenderedSegment.TextSegment>().single().spanned as Spanned
            val span = text.getSpans(0, text.length, AsyncImageSpan::class.java).single()
            assertEquals("\uFFFC", text.subSequence(text.getSpanStart(span), text.getSpanEnd(span)).toString())
            val view = TextView(context)
            view.text = text
            fun layoutAndCountPlaceholderPixels(): Int {
                view.measure(View.MeasureSpec.makeMeasureSpec(160, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                view.layout(0, 0, view.measuredWidth, view.measuredHeight)
                val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                view.draw(android.graphics.Canvas(bitmap))
                val pixels = IntArray(bitmap.width * bitmap.height)
                bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                return pixels.count { it == color }
            }
            val loadingPixels = layoutAndCountPlaceholderPixels()
            val loadingHeight = view.height
            assertTrue("Loading placeholder missing: $source", loadingPixels > 100)
            span.attach(loader, CoroutineScope(Dispatchers.Unconfined), view)
            assertEquals(loadingPixels, layoutAndCountPlaceholderPixels())
            assertEquals(loadingHeight, view.height)
            assertEquals(text.toString(), view.text.toString())
            span.cancel()
        }
    }

    @Test fun loadedImageRebuildsLineHeightAndWrapping() {
        val textView = TextView(ApplicationProvider.getApplicationContext())
        val span = AsyncImageSpan("mock", "image", 300, 400, 0f, Color.GRAY)
        val text = SpannableString("A\uFFFCB")
        text.setSpan(span, 1, 2, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        textView.text = text
        fun measure() {
            textView.measure(View.MeasureSpec.makeMeasureSpec(240, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            textView.layout(0, 0, 240, textView.measuredHeight)
        }
        measure()
        val oldHeight = textView.height
        val oldLayout = textView.layout
        val loader = object : THKImageLoader {
            override suspend fun load(url: String): Bitmap = Bitmap.createBitmap(120, 64, Bitmap.Config.ARGB_8888)
        }
        span.attach(loader, CoroutineScope(Dispatchers.Unconfined), textView)
        measure()
        assertNotSame(oldLayout, textView.layout)
        assertEquals(1, textView.lineCount)
        assertTrue(textView.height < oldHeight)
        assertEquals("A\uFFFCB", textView.text.toString())
        assertSame(span, (textView.text as Spanned).getSpans(1, 2, AsyncImageSpan::class.java).single())
        span.cancel()
    }
}
