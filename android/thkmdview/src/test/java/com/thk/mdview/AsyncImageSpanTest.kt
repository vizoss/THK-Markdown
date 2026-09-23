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
