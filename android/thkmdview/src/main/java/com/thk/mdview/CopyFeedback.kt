package com.thk.mdview

import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.PopupWindow
import android.widget.TextView

/** Anchored overlay: never changes message height or gets clipped by a short code block. */
internal class CopyFeedback {
    var popup: PopupWindow? = null
        private set
    private var label: TextView? = null
    private var hide: Runnable? = null

    fun show(anchor: View, theme: THKMDTheme) {
        dismiss()
        if (!anchor.isAttachedToWindow) return
        val density = anchor.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()
        val message = TextView(anchor.context).apply {
            text = context.getString(R.string.thkmdview_copied)
            textSize = theme.copyFeedbackFontSizeSp
            setTextColor(theme.copyFeedbackTextColor)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(4), dp(10), dp(4))
            background = GradientDrawable().apply {
                setColor(theme.copyFeedbackBackgroundColor)
                cornerRadius = dp(6).toFloat()
            }
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            alpha = 0f
        }
        val available = anchor.resources.displayMetrics.widthPixels
        message.measure(View.MeasureSpec.makeMeasureSpec(available, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        val window = PopupWindow(message, message.measuredWidth, message.measuredHeight, false).apply {
            isTouchable = false
            isOutsideTouchable = false
            elevation = 0f
        }
        popup = window
        label = message
        // Right-align with the pressed button, 4dp below, matching iOS.
        window.showAsDropDown(anchor, anchor.width - message.measuredWidth, dp(4), Gravity.LEFT)
        message.animate().alpha(1f).setDuration(150).start()
        val task = Runnable {
            if (popup === window) {
                message.animate().alpha(0f).setDuration(200).withEndAction {
                    if (popup === window) dismiss()
                }.start()
            }
        }
        hide = task
        message.postDelayed(task, 750)
    }

    fun dismiss() {
        hide?.let { label?.removeCallbacks(it) }
        hide = null
        label?.animate()?.cancel()
        popup?.dismiss()
        popup = null
        label = null
    }
}
