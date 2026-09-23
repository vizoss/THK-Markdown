package com.thk.mdview.sample

import android.content.Intent
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/** Shared flat header; all three destinations are normal back-stack activities. */
open class DemoPageActivity : AppCompatActivity() {
    protected fun installHeader(title: String, back: Boolean = true, theme: Boolean = true) {
        findViewById<TextView>(R.id.pageTitle).text = title
        findViewById<Button>(R.id.backButton).apply {
            visibility = if (back) View.VISIBLE else View.GONE
            setOnClickListener { finish() }
        }
        findViewById<Button>(R.id.themeButton).apply {
            visibility = if (theme) View.VISIBLE else View.GONE
            setOnClickListener { startActivity(Intent(this@DemoPageActivity, ThemeSettingsActivity::class.java)) }
        }
    }

    protected fun setPage(title: String, content: View, back: Boolean = true, theme: Boolean = true) {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.color.demo_surface)
        }
        layoutInflater.inflate(R.layout.demo_header, root, true)
        root.addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
        installHeader(title, back, theme)
    }
}
