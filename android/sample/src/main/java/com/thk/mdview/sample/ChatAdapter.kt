package com.thk.mdview.sample

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.thk.mdview.THKMDView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

enum class Role { USER, ASSISTANT }

data class ChatMessage(val id: Long, val role: Role, val content: String)

private const val VIEW_TYPE_USER = 0
private const val VIEW_TYPE_ASSISTANT = 1

class ChatAdapter(
    private val messages: MutableList<ChatMessage> = mutableListOf(),
    private val onAssistantContentUpdated: () -> Unit = {},
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    class UserViewHolder(itemView: View, val textView: TextView) : RecyclerView.ViewHolder(itemView)

    class AssistantViewHolder(itemView: View, val markdownView: THKMDView) : RecyclerView.ViewHolder(itemView) {
        // One coroutine scope per view holder, reused across rebinds; only the
        // in-flight streaming Job is cancelled on recycle, not the scope itself.
        val scope = CoroutineScope(Dispatchers.Main.immediate + Job())
        var streamingJob: Job? = null
    }

    /** Appends a message and returns its new adapter position. */
    fun addMessage(message: ChatMessage): Int {
        messages.add(message)
        val position = messages.size - 1
        notifyItemInserted(position)
        return position
    }

    override fun getItemViewType(position: Int): Int =
        if (messages[position].role == Role.USER) VIEW_TYPE_USER else VIEW_TYPE_ASSISTANT

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return if (viewType == VIEW_TYPE_USER) {
            val itemView = inflater.inflate(R.layout.item_message_user, parent, false)
            UserViewHolder(itemView, itemView.findViewById(R.id.messageText))
        } else {
            val itemView = inflater.inflate(R.layout.item_message_assistant, parent, false)
            AssistantViewHolder(itemView, itemView.findViewById(R.id.markdownView))
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val message = messages[position]
        when (holder) {
            is UserViewHolder -> holder.textView.text = message.content
            is AssistantViewHolder -> bindAssistant(holder, message)
        }
    }

    private fun bindAssistant(holder: AssistantViewHolder, message: ChatMessage) {
        holder.streamingJob?.cancel()
        holder.markdownView.reset()

        holder.streamingJob = holder.scope.launch {
            val chunkSizes = 3..9
            var index = 0
            val text = message.content
            while (index < text.length) {
                val size = Random.nextInt(chunkSizes.first, chunkSizes.last + 1)
                val end = minOf(index + size, text.length)
                holder.markdownView.appendMarkdownChunk(text.substring(index, end))
                index = end
                onAssistantContentUpdated()
                delay(Random.nextLong(30L, 80L))
            }
        }
    }

    override fun onViewRecycled(holder: RecyclerView.ViewHolder) {
        if (holder is AssistantViewHolder) {
            holder.streamingJob?.cancel()
            holder.streamingJob = null
            holder.markdownView.reset()
        }
    }

    override fun getItemCount(): Int = messages.size

    override fun getItemId(position: Int): Long = messages[position].id
}
