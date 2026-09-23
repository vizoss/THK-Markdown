package com.thk.mdview

import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

@RunWith(AndroidJUnit4::class)
class THKMathCoalescingTest {
    @Test fun sharedRequestSurvivesSingleSubscriberCancellation() {
        val engine = THKMathEngine
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val scope = CoroutineScope(Dispatchers.Main)
        val first = scope.async { engine.render(context, "thk-math://inline/eA", THKMDTheme.Default) }
        val second = scope.async { engine.render(context, "thk-math://inline/eA", THKMDTheme.Default) }
        val field = engine.javaClass.getDeclaredField("waiting").apply { isAccessible = true }
        val finish = engine.javaClass.getDeclaredMethod("finish", String::class.java, THKMathEngine.Result::class.java).apply { isAccessible = true }
        try {
            shadowOf(Looper.getMainLooper()).idle()
            val waiting = field.get(engine) as Map<*, *>
            assertEquals(1, waiting.size)
            val id = waiting.keys.single() as String
            val entry = waiting.values.single()!!
            val subscribers = entry.javaClass.getDeclaredField("subscribers").apply { isAccessible = true }
            assertEquals(2, (subscribers.get(entry) as Map<*, *>).size)
            first.cancel()
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(1, (subscribers.get(entry) as Map<*, *>).size)
            assertFalse(second.isCompleted)
            finish.invoke(engine, id, null)
            shadowOf(Looper.getMainLooper()).idle()
            assertTrue(second.isCompleted)
            assertNull(runBlocking { second.await() })
            assertTrue(waiting.isEmpty())
        } finally {
            first.cancel(); second.cancel()
            (field.get(engine) as Map<*, *>).keys.toList().forEach { finish.invoke(engine, it, null) }
        }
    }
}
