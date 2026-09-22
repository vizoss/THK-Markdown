package com.thk.mdview.sample

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.thk.mdview.THKMDView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

data class ChatMessage(val id: Long, val fullMarkdown: String)

class ChatAdapter(private val messages: List<ChatMessage>) :
    RecyclerView.Adapter<ChatAdapter.MessageViewHolder>() {

    class MessageViewHolder(itemView: View, val markdownView: THKMDView) : RecyclerView.ViewHolder(itemView) {
        // One coroutine scope per view holder, reused across rebinds; only the
        // in-flight streaming Job is cancelled on recycle, not the scope itself.
        val scope = CoroutineScope(Dispatchers.Main.immediate + Job())
        var streamingJob: Job? = null
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): MessageViewHolder {
        val itemView = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_message, parent, false)
        val markdownView = itemView.findViewById<THKMDView>(R.id.markdownView)
        return MessageViewHolder(itemView, markdownView)
    }

    override fun onBindViewHolder(holder: MessageViewHolder, position: Int) {
        val message = messages[position]

        holder.streamingJob?.cancel()
        holder.markdownView.reset()

        holder.streamingJob = holder.scope.launch {
            val chunkSizes = 3..9
            var index = 0
            val text = message.fullMarkdown
            while (index < text.length) {
                val size = Random.nextInt(chunkSizes.first, chunkSizes.last + 1)
                val end = minOf(index + size, text.length)
                holder.markdownView.appendMarkdownChunk(text.substring(index, end))
                index = end
                delay(Random.nextLong(30L, 80L))
            }
        }
    }

    override fun onViewRecycled(holder: MessageViewHolder) {
        holder.streamingJob?.cancel()
        holder.streamingJob = null
        holder.markdownView.reset()
    }

    override fun getItemCount(): Int = messages.size

    override fun getItemId(position: Int): Long = messages[position].id
}
