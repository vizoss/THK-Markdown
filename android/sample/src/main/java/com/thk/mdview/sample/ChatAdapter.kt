package com.thk.mdview.sample

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.thk.mdview.THKMDTheme
import com.thk.mdview.THKMDView
import com.thk.mdview.THKSSEState

enum class Role { USER, ASSISTANT }
data class ChatMessage(val id: Long, val role: Role, val content: String)

/** Message state survives cell recycling; playback belongs to the activity. */
class ChatAdapter(
    private val onAssistantContentUpdated: () -> Unit = {},
    private val onRetryMessage: ((Long) -> Unit)? = null,
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
    private val messages = mutableListOf<ChatMessage>()
    private val holders = mutableSetOf<AssistantViewHolder>()
    private val sseStates = mutableMapOf<Long, Pair<THKSSEState, String?>>()
    private var currentTheme: THKMDTheme = THKMDTheme.Default
    val theme: THKMDTheme get() = currentTheme

    class UserViewHolder(itemView: View, val text: TextView) : RecyclerView.ViewHolder(itemView)
    class AssistantViewHolder(itemView: View, val markdown: THKMDView) : RecyclerView.ViewHolder(itemView) {
        var messageId: Long? = null
    }

    init { setHasStableIds(true) }

    fun setTheme(value: THKMDTheme) {
        currentTheme = value
        holders.forEach { it.markdown.theme = value }
    }

    fun clearMessages() {
        holders.forEach { it.messageId = null; it.markdown.reset() }
        messages.clear()
        sseStates.clear()
        notifyDataSetChanged()
    }

    fun addMessage(message: ChatMessage) {
        messages += message
        notifyItemInserted(messages.lastIndex)
    }

    fun appendChunk(id: Long, chunk: String) {
        val index = messages.indexOfFirst { it.id == id }
        if (index < 0) return
        messages[index] = messages[index].copy(content = messages[index].content + chunk)
        holders.filter { it.messageId == id }.forEach { it.markdown.appendMarkdownChunk(chunk) }
        onAssistantContentUpdated()
    }

    fun setSSEState(id: Long, state: THKSSEState, error: String? = null) {
        sseStates[id] = state to error
        holders.filter { it.messageId == id }.forEach { holder ->
            holder.markdown.sseEnabled = true
            holder.markdown.setSSEState(state, error)
        }
        onAssistantContentUpdated()
    }
    fun replaceContent(id: Long, content: String) {
        val index = messages.indexOfFirst { it.id == id }
        if (index < 0) return
        messages[index] = messages[index].copy(content = content)
        holders.filter { it.messageId == id }.forEach { it.markdown.setMarkdown(content) }
    }

    override fun getItemCount() = messages.size
    override fun getItemId(position: Int) = messages[position].id
    override fun getItemViewType(position: Int) = if (messages[position].role == Role.USER) 0 else 1

    override fun onCreateViewHolder(parent: ViewGroup, type: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return if (type == 0) {
            val view = inflater.inflate(R.layout.item_message_user, parent, false)
            UserViewHolder(view, view.findViewById(R.id.messageText))
        } else {
            val view = inflater.inflate(R.layout.item_message_assistant, parent, false)
            AssistantViewHolder(view, view.findViewById(R.id.markdownView)).also { holder ->
                holder.markdown.imageLoader = FixtureImageLoader(parent.context)
                holder.markdown.addOnLayoutChangeListener { _, _, top, _, bottom, _, oldTop, _, oldBottom ->
                    if (bottom - top != oldBottom - oldTop) onAssistantContentUpdated()
                }
                holder.markdown.onLinkClick = { url ->
                    android.widget.Toast.makeText(parent.context, "链接：$url", android.widget.Toast.LENGTH_SHORT).show()
                    true
                }
                holder.markdown.onImageClick = { url ->
                    android.widget.Toast.makeText(parent.context, "图片：$url", android.widget.Toast.LENGTH_SHORT).show()
                    true
                }
            }
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val message = messages[position]
        when (holder) {
            is UserViewHolder -> holder.text.text = message.content
            is AssistantViewHolder -> {
                holder.messageId = message.id
                holder.markdown.reset()
                holder.markdown.theme = theme
                holder.markdown.setMarkdown(message.content)
                holder.markdown.sseEnabled = sseStates.containsKey(message.id)
                holder.markdown.onRetry = onRetryMessage?.let { callback -> { holder.messageId?.let(callback) } }
                sseStates[message.id]?.let { holder.markdown.setSSEState(it.first, it.second) }
                holders += holder
            }
        }
    }

    override fun onViewRecycled(holder: RecyclerView.ViewHolder) {
        if (holder is AssistantViewHolder) {
            holder.messageId = null
            holder.markdown.reset()
            holder.markdown.onRetry = null
            holders -= holder
        }
    }
}
