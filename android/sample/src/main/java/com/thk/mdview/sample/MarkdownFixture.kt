package com.thk.mdview.sample

import android.content.Context
import android.graphics.Bitmap
import com.thk.mdview.THKImageLoader
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

data class MarkdownFixture(
    val id: String, val title: String, val markdown: String,
    val chunks: List<String>, val notes: List<String>, val history: List<String>, val copyTexts: List<String>
) {
    val summary get() = "$id · $title\n" + notes.joinToString("\n") +
        "\n预期复制内容：\n" + if (copyTexts.isEmpty()) "按块检查，无固定断言" else copyTexts.joinToString("\n——\n")
    companion object {
        fun loadAll(context: Context): List<MarkdownFixture> = listOf("p0", "p1", "p2").flatMap { load(context, it) }

        fun load(context: Context, suite: String = "p0"): List<MarkdownFixture> {
            require(suite in listOf("p0", "p1", "p2"))
            val catalog = JSONObject(context.assets.open("$suite.json").bufferedReader().use { it.readText() })
            require(catalog.getInt("schemaVersion") == 1)
            val cases = catalog.getJSONArray("cases")
            val result = (0 until cases.length()).map { index ->
                val value = cases.getJSONObject(index)
                MarkdownFixture(value.getString("id"), value.getString("title"), value.getString("markdown"),
                    value.getJSONArray("chunks").strings(), value.getJSONObject("expected").getJSONArray("notes").strings(),
                    value.optJSONArray("history")?.strings().orEmpty(), value.getJSONObject("expected").getJSONArray("copyTexts").strings())
            }
            require(result.map { it.id }.distinct().size == result.size)
            require(result.isNotEmpty())
            require(result.all { it.chunks.isNotEmpty() && it.chunks.joinToString("") == it.markdown })
            return result
        }
        private fun JSONArray.strings() = (0 until length()).map { getString(it) }
    }
}

/** P0 images are deterministic and offline, including delayed failure. */
class FixtureImageLoader(context: Context) : THKImageLoader {
    private val density = context.resources.displayMetrics.density
    override suspend fun load(url: String): Bitmap? {
        delay(200)
        if (url != "https://fixtures.thk.invalid/ok.png") return null
        // Match the iOS fixture's 120 × 64 logical points, not raw device pixels.
        return Bitmap.createBitmap((120 * density).toInt(), (64 * density).toInt(), Bitmap.Config.ARGB_8888)
            .apply { eraseColor(0xFF0A84FF.toInt()) }
    }
}
