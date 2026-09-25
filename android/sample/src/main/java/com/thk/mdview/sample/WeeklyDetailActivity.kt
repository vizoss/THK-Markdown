package com.thk.mdview.sample

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.*
import androidx.lifecycle.lifecycleScope
import com.thk.mdview.THKMDView
import kotlinx.coroutines.*
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicReference

class WeeklyDetailActivity : DemoPageActivity() {
    private lateinit var markdown: THKMDView
    private lateinit var status: Button
    private lateinit var article: WeeklyArticle
    private var request: Job? = null
    private val connection = AtomicReference<HttpURLConnection?>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        article = WeeklyArticle.load(this).firstOrNull { it.number == intent.getIntExtra("issue", -1) }
            ?: run { finish(); return }
        val stack = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val p = (16 * resources.displayMetrics.density).toInt()
            setPadding(p, p, p, p)
        }
        val source = Button(this).apply {
            text = "阮一峰 · 科技爱好者周刊 · 查看原文 ↗"
            isAllCaps = false; textSize = 13f
            setBackgroundResource(R.drawable.demo_control)
            setOnClickListener { openLink(article.sourceURL) }
        }
        status = Button(this).apply { isAllCaps = false; setOnClickListener { loadArticle() } }
        markdown = THKMDView(this).apply {
            theme = DemoThemeStore.load(this@WeeklyDetailActivity)
            onLinkClick = { link ->
                runCatching { java.net.URI(article.sourceURL).resolve(link).toString() }
                    .getOrNull()?.let { openLink(it) }
                true
            }
        }
        val gap = (12 * resources.displayMetrics.density).toInt()
        stack.addView(source, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = gap })
        stack.addView(status, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = gap })
        stack.addView(markdown, LinearLayout.LayoutParams(-1, -2))
        setPage("第 ${article.number} 期", ScrollView(this).apply { addView(stack) })
        loadArticle()
    }

    private fun openLink(url: String) {
        val uri = Uri.parse(url)
        if (uri.scheme !in listOf("https", "http", "mailto")) return
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }.onFailure {
            Toast.makeText(this, "无法打开链接", Toast.LENGTH_SHORT).show()
        }
    }

    private fun loadArticle() {
        request?.cancel()
        connection.getAndSet(null)?.disconnect()
        status.visibility = View.VISIBLE; status.text = "正在加载…"; status.isEnabled = false
        val url = article.rawURL
        request = lifecycleScope.launch {
            try {
                val content = withContext(Dispatchers.IO) {
                    val conn = URL(url).openConnection() as HttpURLConnection
                    conn.connectTimeout = 15_000; conn.readTimeout = 20_000
                    connection.set(conn)
                    try {
                        ensureActive()
                        check(conn.responseCode == 200) { "HTTP ${conn.responseCode}" }
                        val bytes = conn.inputStream.use { input ->
                            val out = java.io.ByteArrayOutputStream()
                            val buffer = ByteArray(8192)
                            while (true) {
                                ensureActive()
                                val count = input.read(buffer)
                                if (count < 0) break
                                check(out.size() + count <= 2_000_000) { "文章过大" }
                                out.write(buffer, 0, count)
                            }
                            out.toByteArray()
                        }
                        String(bytes, Charsets.UTF_8).also { check(it.isNotBlank()) }
                    } finally { connection.compareAndSet(conn, null); conn.disconnect() }
                }
                markdown.setMarkdown(content)
                status.visibility = View.GONE
            } catch (error: CancellationException) { throw error }
            catch (_: Exception) { status.text = "加载失败，请检查网络 · 点击重试"; status.isEnabled = true }
        }
    }

    override fun onResume() {
        super.onResume()
        if (::markdown.isInitialized) markdown.theme = DemoThemeStore.load(this)
    }

    override fun onDestroy() {
        request?.cancel(); connection.getAndSet(null)?.disconnect()
        if (::markdown.isInitialized) markdown.reset()
        super.onDestroy()
    }
}
