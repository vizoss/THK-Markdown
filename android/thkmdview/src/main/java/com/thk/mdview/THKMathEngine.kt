package com.thk.mdview

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.LruCache
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.util.UUID

/** One offline rasterizer, bounded cache/pending queue. No Activity or message retained. */
internal object THKMathEngine {
    data class Result(val bitmap: Bitmap, val descentPx: Float)
    private data class Pending(val key: String, val request: JSONObject,
        val subscribers: MutableMap<String, (Result?) -> Unit> = linkedMapOf())
    private val handler = Handler(Looper.getMainLooper())
    private var web: WebView? = null
    private var loaded = false
    private val waiting = linkedMapOf<String, Pending>()
    private val inFlight = mutableMapOf<String, String>()
    private var cacheLimitBytes = 8 * 1024 * 1024
    fun configureCache(maxBytes: Int) {
        check(Looper.myLooper() == Looper.getMainLooper()) { "Call on the main thread" }
        require(maxBytes >= 0) { "maxBytes must be nonnegative" }
        cacheLimitBytes = maxBytes
        cache.evictAll()
        cache.resize(maxBytes.coerceAtLeast(1))
    }
    fun clearCache() {
        check(Looper.myLooper() == Looper.getMainLooper()) { "Call on the main thread" }
        cache.evictAll()
    }
    private val cache = object : LruCache<String, Result>(8 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Result) = value.bitmap.byteCount
    }

    fun source(url: String): String? = runCatching {
        val uri = Uri.parse(url)
        if (uri.scheme != "thk-math" || uri.host !in listOf("inline", "display")) return null
        val encoded = uri.path.orEmpty().drop(1)
        if (encoded.length > 12000) return null
        String(Base64.decode(encoded, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING), Charsets.UTF_8)
    }.getOrNull()

    suspend fun render(context: Context, url: String, theme: THKMDTheme): Result? = withContext(Dispatchers.Main) {
        val tex = source(url) ?: return@withContext null
        val metrics = context.resources.displayMetrics
        val size = (theme.bodyFontSizeSp * theme.mathScale * metrics.scaledDensity / metrics.density).coerceIn(1f, 96f)
        val color = "rgba(${Color.red(theme.bodyTextColor)},${Color.green(theme.bodyTextColor)},${Color.blue(theme.bodyTextColor)},${Color.alpha(theme.bodyTextColor) / 255.0})"
        val key = "$url|$size|$color|${metrics.density}"
        cache.get(key)?.let { return@withContext it }
        if ((key !in inFlight && waiting.size >= 64) || waiting.values.sumOf { it.subscribers.size } >= 256) return@withContext null
        start(context.applicationContext)
        suspendCancellableCoroutine { continuation ->
            val subscriber = UUID.randomUUID().toString()
            val existing = inFlight[key]
            val id = existing ?: UUID.randomUUID().toString()
            val entry = waiting[id] ?: Pending(key, JSONObject().put("id", id).put("tex", tex)
                .put("display", Uri.parse(url).host == "display").put("size", size).put("color", color).put("scale", metrics.density))
            entry.subscribers[subscriber] = { result ->
                if (continuation.isActive) continuation.resumeWith(kotlin.Result.success(result))
            }
            waiting[id] = entry
            inFlight[key] = id
            if (existing == null) {
                if (loaded) send(entry.request)
                handler.postDelayed({ finish(id, null) }, 10_000)
            }
            // Keep the underlying render until completion/timeout, even if all current
            // subscribers cancel: a stream rebind can join it instead of enqueueing again.
            continuation.invokeOnCancellation { handler.post { waiting[id]?.subscribers?.remove(subscriber) } }
        }
    }

    private fun start(context: Context) {
        if (web != null) return
        val view = WebView(context)
        view.settings.javaScriptEnabled = true
        view.settings.allowContentAccess = false
        view.settings.allowFileAccess = true
        view.settings.blockNetworkLoads = true
        view.addJavascriptInterface(Bridge(context.resources.displayMetrics.density), "MathBridge")
        view.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String?) {
                loaded = true
                waiting.values.toList().forEach { send(it.request) }
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = true
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                val path = request.url.toString()
                if (path == "file:///android_asset/math_template.html" || path == "file:///android_asset/mathjax-3.2.2.js") return null
                return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(byteArrayOf()))
            }
        }
        web = view
        view.loadUrl("file:///android_asset/math_template.html")
    }
    private fun send(request: JSONObject) { web?.evaluateJavascript("window.renderMath($request)", null) }
    private fun finish(id: String, result: Result?) {
        val item = waiting.remove(id) ?: return
        inFlight.remove(item.key)
        if (result != null && cacheLimitBytes > 0 && result.bitmap.byteCount <= cacheLimitBytes) cache.put(item.key, result)
        item.subscribers.values.forEach { it(result) }
    }
    private class Bridge(private val density: Float) {
        @JavascriptInterface fun result(json: String) {
            val value = runCatching { JSONObject(json) }.getOrNull() ?: return
            val id = value.optString("id")
            val result = runCatching {
                val width = value.getDouble("width"); val height = value.getDouble("height")
                require(width > 0 && height > 0 && width <= 4096 && height <= 2048)
                val bytes = Base64.decode(value.getString("png"), Base64.DEFAULT)
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: error("bitmap")
                val scaled = Bitmap.createScaledBitmap(bitmap, (width * density).toInt().coerceAtLeast(1), (height * density).toInt().coerceAtLeast(1), true)
                Result(scaled, (value.getDouble("descent") * density).toFloat())
            }.getOrNull()
            handler.post { finish(id, result) }
        }
    }
}
