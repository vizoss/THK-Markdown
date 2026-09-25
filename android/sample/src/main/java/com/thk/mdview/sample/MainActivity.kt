package com.thk.mdview.sample

import android.content.Intent
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatButton

/** Launcher only: no message, fixture playback or theme editor state here. */
class MainActivity : DemoPageActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val density = resources.displayMetrics.density
        val stack = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val padding = (16 * density).toInt()
            setPadding(padding, padding, padding, padding)
        }
        val entries = listOf(
            "ShowCase 格式显示" to ShowCaseActivity::class.java,
            "SSE Chat" to SSEChatActivity::class.java,
            "科技周刊 · 50 篇" to WeeklyListActivity::class.java,
            "主题设置" to ThemeSettingsActivity::class.java
        )
        entries.forEach { (label, destination) ->
            val button = AppCompatButton(this, null, 0).apply {
                text = label + "  ›"
                isAllCaps = false
                gravity = android.view.Gravity.CENTER
                includeFontPadding = false
                setPadding(0, 0, 0, 0)
                minWidth = 0
                minHeight = 0
                typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, resources.getDimension(R.dimen.demo_font))
                setTextColor(androidx.core.content.ContextCompat.getColor(context, R.color.demo_ink))
                setBackgroundResource(R.drawable.demo_control)
                setOnClickListener { startActivity(Intent(this@MainActivity, destination)) }
            }
            stack.addView(button, LinearLayout.LayoutParams(-1, (64 * density).toInt()).apply { bottomMargin = (12 * density).toInt() })
        }
        setPage("THKMDView Demo", ScrollView(this).apply { addView(stack) }, back = false, theme = false)
    }
}
