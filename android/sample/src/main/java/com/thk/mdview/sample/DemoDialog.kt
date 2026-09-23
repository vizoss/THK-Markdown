package com.thk.mdview.sample

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.widget.AppCompatButton
import androidx.core.content.ContextCompat

/** Flat demo modal, mirrored by iOS DemoDialogController; no native alert styling. */
object DemoDialog {
    fun show(activity: Activity, title: String, body: String? = null,
             choices: List<String> = emptyList(), selected: Int = -1, onSelect: (Int) -> Unit = {}) {
        fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
        fun color(id: Int) = ContextCompat.getColor(activity, id)
        fun fontSize(id: Int) = activity.resources.getDimension(id) / activity.resources.displayMetrics.scaledDensity
        val dialog = Dialog(activity)
        val card = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            background = GradientDrawable().apply {
                setColor(color(R.color.demo_surface)); cornerRadius = dp(12).toFloat()
            }
        }
        card.addView(TextView(activity).apply {
            text = title; textSize = fontSize(R.dimen.demo_title); setTextColor(color(R.color.demo_ink))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            maxLines = 2
        }, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(16) })
        val content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        if (body != null) content.addView(TextView(activity).apply {
            text = body; textSize = fontSize(R.dimen.demo_font); setTextColor(color(R.color.demo_ink))
            setLineSpacing(dp(4).toFloat(), 1f); setTextIsSelectable(true)
        })
        choices.forEachIndexed { index, label ->
            content.addView(TextView(activity).apply {
                text = (if (index == selected) "✓  " else "") + label
                textSize = fontSize(R.dimen.demo_font); gravity = Gravity.CENTER_VERTICAL
                typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
                minHeight = dp(48); setPadding(dp(12), dp(8), dp(12), dp(8))
                setTextColor(color(if (index == selected) R.color.demo_accent else R.color.demo_ink))
                setBackgroundColor(color(if (index == selected) R.color.demo_soft else R.color.demo_surface))
                setOnClickListener { dialog.dismiss(); onSelect(index) }
            }, LinearLayout.LayoutParams(-1, -2))
        }
        val scroll = ScrollView(activity).apply { addView(content); isFillViewport = false }
        card.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        card.addView(AppCompatButton(activity).apply {
            text = "关闭"; textSize = fontSize(R.dimen.demo_font); isAllCaps = false
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
            setTextColor(color(R.color.demo_surface)); setBackgroundResource(R.drawable.demo_primary)
            backgroundTintList = null; stateListAnimator = null; elevation = 0f
            minHeight = 0; minimumHeight = 0; setPadding(0, 0, 0, 0)
            setOnClickListener { dialog.dismiss() }
        }, LinearLayout.LayoutParams(-1, dp(44)).apply { topMargin = dp(16) })
        dialog.setContentView(card)
        dialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setDimAmount(0.32f)
            addFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        }
        dialog.show()
        val bounds = activity.findViewById<android.view.View>(android.R.id.content)
        dialog.window?.setLayout(minOf(bounds.width - dp(32), dp(560)), (bounds.height * 0.7f).toInt())
    }
}
