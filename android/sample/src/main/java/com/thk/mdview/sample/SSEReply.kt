package com.thk.mdview.sample

import android.content.Context
import org.json.JSONArray

internal data class SSEReply(val id: String, val title: String, val chunks: List<String>, val simulateFailure: Boolean) {
    companion object {
        fun load(context: Context): List<SSEReply> {
            val data = JSONArray(context.assets.open("replies.json").bufferedReader().use { it.readText() })
            return (0 until data.length()).map { index ->
                val row = data.getJSONObject(index)
                val chunks = row.getJSONArray("chunks")
                SSEReply(row.getString("id"), row.getString("title"), (0 until chunks.length()).map { chunks.getString(it) }, row.getBoolean("simulateFailure"))
            }
        }
    }
}
