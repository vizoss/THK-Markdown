package com.thk.mdview.sample

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.*
import org.json.JSONArray

internal data class WeeklyArticle(val number: Int, val title: String, val path: String) {
    val sourceURL get() = "https://github.com/ruanyf/weekly/blob/master/$path"
    val rawURL get() = "https://raw.githubusercontent.com/ruanyf/weekly/master/$path"
    companion object {
        fun load(context: Context): List<WeeklyArticle> {
            val json = JSONArray(context.assets.open("weekly.json").bufferedReader().use { it.readText() })
            return (0 until json.length()).map { i -> json.getJSONObject(i).let {
                WeeklyArticle(it.getInt("number"), it.getString("title"), it.getString("path"))
            } }
        }
    }
}

class WeeklyListActivity : DemoPageActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val articles = WeeklyArticle.load(this)
        val list = ListView(this).apply {
            divider = null
            val p = (16 * resources.displayMetrics.density).toInt()
            setPadding(p, 0, p, p)
            clipToPadding = false
            addHeaderView(TextView(context).apply {
                text = "阮一峰 · 科技爱好者周刊\n50 篇 · 第 364–413 期 · 在线阅读"
                setTextColor(0xff64748b.toInt()); textSize = 13f
                setPadding(0, p, 0, p)
            }, null, false)
        }
        list.adapter = object : BaseAdapter() {
            override fun getCount() = articles.size
            override fun getItem(position: Int) = articles[position]
            override fun getItemId(position: Int) = articles[position].number.toLong()
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                val row = convertView as? FrameLayout ?: FrameLayout(this@WeeklyListActivity).apply {
                    val gap = (12 * resources.displayMetrics.density).toInt()
                    setPadding(0, 0, 0, gap)
                    addView(TextView(context).apply {
                        textSize = 16f; setTextColor(0xff1e293b.toInt())
                        val p = (16 * resources.displayMetrics.density).toInt()
                        setPadding(p, p, p, p)
                        minHeight = (76 * resources.displayMetrics.density).toInt()
                        gravity = android.view.Gravity.CENTER_VERTICAL
                        setBackgroundResource(R.drawable.demo_control)
                    }, FrameLayout.LayoutParams(-1, -2))
                }
                val label = row.getChildAt(0) as TextView
                val item = getItem(position)
                label.text = "第 ${item.number} 期  ›\n${item.title}"
                return row
            }
        }
        list.setOnItemClickListener { _, _, position, _ ->
            articles.getOrNull(position - list.headerViewsCount)?.let {
                startActivity(Intent(this, WeeklyDetailActivity::class.java).putExtra("issue", it.number))
            }
        }
        setPage("科技周刊", list)
    }
}
