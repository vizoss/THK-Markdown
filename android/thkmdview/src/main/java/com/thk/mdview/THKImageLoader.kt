package com.thk.mdview

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/** Pluggable image loading for `![]()` Markdown images rendered inline by [THKMDView]. */
interface THKImageLoader {
    /** Loads [url], or returns null on failure/cancellation. Never throws. */
    suspend fun load(url: String): Bitmap?
}

/**
 * Dependency-free default [THKImageLoader]: in-memory LRU + on-disk cache, fetched via
 * [HttpURLConnection]. No Coil/Glide dependency, so hosts that already use one of those
 * can supply their own [THKImageLoader] adapter instead via [THKMDView.imageLoader].
 */
class DefaultTHKImageLoader @JvmOverloads constructor(
    context: Context,
    memoryCacheBytes: Int = (Runtime.getRuntime().maxMemory() / 8).toInt(),
    private val diskCacheDir: File = File(context.applicationContext.cacheDir, "thkmdview_image_cache"),
    private val fetcher: suspend (String) -> ByteArray? = ::fetchOverHttp
) : THKImageLoader {

    private val memoryCache = object : LruCache<String, Bitmap>(memoryCacheBytes) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    override suspend fun load(url: String): Bitmap? = withContext(Dispatchers.IO) {
        memoryCache.get(url)?.let { return@withContext it }

        val diskFile = File(diskCacheDir, sha256(url))
        val bytes = if (diskFile.exists()) {
            runCatching { diskFile.readBytes() }.getOrNull()
        } else {
            fetcher(url)?.also { fetched ->
                runCatching {
                    diskCacheDir.mkdirs()
                    diskFile.writeBytes(fetched)
                }
            }
        } ?: return@withContext null

        val bitmap = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
        bitmap?.also { memoryCache.put(url, it) }
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return digest.joinToString(separator = "") { "%02x".format(it) }
    }
}

// A free function (not a method on DefaultTHKImageLoader) so suspendCancellableCoroutine's
// invokeOnCancellation can force-close the socket via connection.disconnect() and actually
// unblock the in-flight read, instead of merely leaving a CancellationException unhandled
// while the underlying HttpURLConnection keeps blocking a Dispatchers.IO thread.
private suspend fun fetchOverHttp(url: String): ByteArray? = suspendCancellableCoroutine { cont ->
    val connection = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = 10_000
        readTimeout = 10_000
    }
    cont.invokeOnCancellation { connection.disconnect() }
    try {
        connection.connect()
        val bytes = connection.inputStream.use { it.readBytes() }
        if (cont.isActive) cont.resumeWith(Result.success(bytes))
    } catch (t: Throwable) {
        if (cont.isActive) cont.resumeWith(Result.success(null))
    } finally {
        connection.disconnect()
    }
}
