package com.thk.mdview.sample

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.RecyclerView

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val messages = (0 until 12).map { i ->
            ChatMessage(id = i.toLong(), fullMarkdown = SAMPLE_MARKDOWN_DOCS[i % SAMPLE_MARKDOWN_DOCS.size])
        }

        val recyclerView = findViewById<RecyclerView>(R.id.messageList)
        recyclerView.setHasFixedSize(false)
        recyclerView.adapter = ChatAdapter(messages)
    }
}
