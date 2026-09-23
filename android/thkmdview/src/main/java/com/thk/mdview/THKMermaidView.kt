package com.thk.mdview

import android.content.Context
import android.graphics.Typeface
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatTextView
import kotlin.math.roundToInt

/**
 * Renders a ```mermaid fenced block as a real diagram via an embedded [WebView] loading
 * bundled `mermaid.js` (see `assets/mermaid_template.html`/`assets/mermaid.min.js`) - a
 * deliberate, scoped exception to this SDK's general "no WebView" stance (RESEARCH.md
 * §2), analogous in role to [THKTableView]: its own real child view bound by
 * `THKMDView.bindDiagramSegment`, not a span painted into a shared text segment.
 *
 * The diagram's rendered size isn't known upfront, so [WebView] starts at a fixed
 * placeholder height; once the page's own JS reports the real rendered SVG size back
 * through [Bridge], the WebView is resized to match and [View.requestLayout] is called -
 * mirroring how [AsyncImageSpan] swaps in an image's real dimensions once known. Invalid
 * Mermaid syntax is caught on the JS side and falls back to the raw source shown as
 * plain monospaced text, rather than a blank/broken WebView.
 */
class THKMermaidView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : FrameLayout(context, attrs) {

    private val density = context.resources.displayMetrics.density

    private val webView = WebView(context).apply {
        settings.javaScriptEnabled = true
        settings.useWideViewPort = false
        settings.loadWithOverviewMode = false
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
        addJavascriptInterface(Bridge(), "AndroidBridge")
    }

    private val fallbackText = AppCompatTextView(context).apply {
        visibility = View.GONE
        typeface = Typeface.MONOSPACE
        val paddingPx = (12 * this@THKMermaidView.density).toInt()
        setPadding(paddingPx, paddingPx, paddingPx, paddingPx)
    }

    private var currentSource: String? = null
    private var pageLoaded = false

    init {
        webView.layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, dp(DEFAULT_HEIGHT_DP))
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String?) {
                pageLoaded = true
                currentSource?.let { evaluateRender(it) }
            }
        }
        addView(webView)
        addView(fallbackText, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    /** Renders (or re-renders, if [source] changed) the given Mermaid diagram source. */
    fun render(source: String, theme: THKMDTheme) {
        fallbackText.setTextColor(theme.codeTextColor)
        fallbackText.setBackgroundColor(theme.codeBackgroundColor)
        fallbackText.setTextSize(TypedValue.COMPLEX_UNIT_SP, theme.codeFontSizeSp)
        // A closing fence can rebind identical source after the SVG has reported its
        // height. Keep that measured height (and any error fallback) on a no-op bind.
        if (currentSource == source && pageLoaded) return
        fallbackText.visibility = View.GONE
        webView.visibility = View.VISIBLE
        webView.layoutParams = webView.layoutParams.apply { height = dp(DEFAULT_HEIGHT_DP) }
        currentSource = source
        if (pageLoaded) {
            evaluateRender(source)
        } else {
            webView.loadUrl("file:///android_asset/mermaid_template.html")
        }
    }

    /** Tears down the WebView; must be called before this view is discarded (see THKMDView.reset()). */
    fun destroy() {
        pageLoaded = false
        webView.stopLoading()
        webView.removeJavascriptInterface("AndroidBridge")
        webView.webViewClient = object : WebViewClient() {}
        webView.destroy()
    }

    private fun evaluateRender(source: String) {
        // org.json.JSONObject.quote produces a properly-escaped, double-quoted JSON
        // string literal - safe to splice directly into a JS call even if the Mermaid
        // source contains quotes/backticks/newlines/`</script>`-looking text.
        val encoded = org.json.JSONObject.quote(source)
        webView.evaluateJavascript("renderDiagram($encoded)", null)
    }

    // cssWidthPx is unused: the WebView's own width is already MATCH_PARENT-capped to the
    // bubble width, and the template's CSS (`max-width: 100%`) already scaled the SVG to
    // fit it - only the resulting height needs to be read back and applied here.
    private fun onRendered(@Suppress("UNUSED_PARAMETER") cssWidthPx: Double, cssHeightPx: Double) {
        if (cssHeightPx <= 0) return
        val heightPx = (cssHeightPx * density).roundToInt().coerceAtLeast(dp(MIN_HEIGHT_DP))
        webView.layoutParams = webView.layoutParams.apply { height = heightPx }
        webView.requestLayout()
    }

    private fun onRenderError(message: String) {
        webView.visibility = View.GONE
        val source = currentSource.orEmpty()
        fallbackText.text = "$source\n\n($FALLBACK_NOTE: $message)"
        fallbackText.visibility = View.VISIBLE
    }

    private fun dp(value: Int): Int = (value * density).toInt()

    // WebView's JS bridge calls land on the WebView's own worker thread, never the main
    // thread - every method here hops back via webView.post before touching any View.
    private inner class Bridge {
        @JavascriptInterface
        fun onDiagramRendered(width: Double, height: Double) {
            webView.post { onRendered(width, height) }
        }

        @JavascriptInterface
        fun onDiagramError(message: String) {
            webView.post { onRenderError(message) }
        }
    }

    private companion object {
        const val DEFAULT_HEIGHT_DP = 160
        const val MIN_HEIGHT_DP = 60
        const val FALLBACK_NOTE = "diagram failed to render"
    }
}
