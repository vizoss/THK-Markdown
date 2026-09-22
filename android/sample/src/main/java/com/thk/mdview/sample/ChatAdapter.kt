package com.thk.mdview.sample

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.thk.mdview.THKMDTheme
import com.thk.mdview.THKMDView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.random.Random

enum class Role { USER, ASSISTANT }

data class ChatMessage(val id: Long, val role: Role, val content: String)

private const val VIEW_TYPE_USER = 0
private const val VIEW_TYPE_ASSISTANT = 1

class ChatAdapter(
    private val streamScope: CoroutineScope,
    private val messages: MutableList<ChatMessage> = mutableListOf(),
    private val onAssistantContentUpdated: () -> Unit = {},
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    class UserViewHolder(itemView: View, val textView: TextView) : RecyclerView.ViewHolder(itemView)

    class AssistantViewHolder(itemView: View, val markdownView: THKMDView) : RecyclerView.ViewHolder(itemView) {
        // Streaming belongs to the message, so recycling only unbinds this view.
        var messageId: Long? = null
    }

    // Bound assistant holders are tracked so setTheme() can update THKMDView.theme on
    // whatever's currently on screen directly, proving a theme change re-renders in
    // place without touching streamed content (no reset()/re-stream involved).
    private val boundAssistantHolders = mutableSetOf<AssistantViewHolder>()
    private var currentTheme: THKMDTheme = THKMDTheme.Default

    /** The theme last pushed via [setTheme] - lets a caller (e.g. the theme settings
     *  sheet) seed its controls from what's actually on screen instead of tracking a
     *  second copy of the current theme itself. */
    val theme: THKMDTheme get() = currentTheme

    // A message only plays its chunk-by-chunk "typewriter" once. Without this, every
    // RecyclerView rebind of an already-finished message - which happens constantly
    // while scrolling, since recycled views get rebound on essentially every scroll
    // frame - would restart the whole streaming coroutine from scratch, competing with
    // the scroll gesture for main-thread time and re-typing text the user already read.
    private val fullyStreamedMessageIds = mutableSetOf<Long>()
    private val streamedContent = mutableMapOf<Long, String>()

    fun setTheme(theme: THKMDTheme) {
        currentTheme = theme
        boundAssistantHolders.forEach { it.markdownView.theme = theme }
    }

    /** Appends a message and returns its new adapter position. */
    fun addMessage(message: ChatMessage): Int {
        messages.add(message)
        val position = messages.size - 1
        notifyItemInserted(position)
        if (message.role == Role.ASSISTANT) {
            streamedContent[message.id] = ""
            streamScope.launch {
                var index = 0
                while (index < message.content.length) {
                    val end = minOf(index + Random.nextInt(3, 10), message.content.length)
                    val chunk = message.content.substring(index, end)
                    streamedContent[message.id] = message.content.substring(0, end)
                    boundAssistantHolders.filter { it.messageId == message.id }.forEach {
                        it.markdownView.appendMarkdownChunk(chunk)
                    }
                    index = end
                    onAssistantContentUpdated()
                    delay(Random.nextLong(30L, 80L))
                }
                fullyStreamedMessageIds += message.id
            }
        }
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
            val holder = AssistantViewHolder(itemView, itemView.findViewById(R.id.markdownView))
            holder
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
        holder.messageId = message.id
        holder.markdownView.reset()
        holder.markdownView.theme = currentTheme
        boundAssistantHolders += holder

        if (message.id in fullyStreamedMessageIds) {
            holder.markdownView.setMarkdown(message.content)
            return
        }

        holder.markdownView.setMarkdown(streamedContent[message.id].orEmpty())
    }

    override fun onViewRecycled(holder: RecyclerView.ViewHolder) {
        if (holder is AssistantViewHolder) {
            holder.messageId = null
            holder.markdownView.reset()
            boundAssistantHolders -= holder
        }
    }

    override fun getItemCount(): Int = messages.size

    override fun getItemId(position: Int): Long = messages[position].id
}
