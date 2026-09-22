package com.thk.mdview

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.common.truth.Truth.assertThat
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith

// A real (not just well-formed-looking) 4x4 solid-color PNG produced by a standard
// encoder, so BitmapFactory.decodeByteArray succeeds the same way under both
// Robolectric's legacy and native graphics modes (a hand-rolled "smallest possible
// PNG" byte trick was tried first and tripped OpenJDK's PNG reader - robolectric#6812).
private const val TEST_PNG_HEX = "89504E470D0A1A0A0000000D49484452000000040000000408020000002693092900000011" +
    "49444154789C63FCCF80004C486C3C1C0033D1010730E7E14C0000000049454E44AE426082"

private fun hexToBytes(hex: String): ByteArray =
    ByteArray(hex.length / 2) { i ->
        ((Character.digit(hex[i * 2], 16) shl 4) + Character.digit(hex[i * 2 + 1], 16)).toByte()
    }

@RunWith(AndroidJUnit4::class)
class DefaultTHKImageLoaderTest {

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val testPng = hexToBytes(TEST_PNG_HEX)

    private fun freshDiskCacheDir(name: String): File =
        File(context.cacheDir, name).also { it.deleteRecursively() }

    @Test
    fun memoryCacheHit_avoidsCallingTheFetcherASecondTime() = runTest {
        var fetchCount = 0
        val loader = DefaultTHKImageLoader(
            context = context,
            diskCacheDir = freshDiskCacheDir("mem-test"),
            fetcher = { fetchCount++; testPng }
        )

        val first = loader.load("https://example.com/a.png")
        val second = loader.load("https://example.com/a.png")

        assertThat(first).isNotNull()
        assertThat(second).isNotNull()
        assertThat(fetchCount).isEqualTo(1)
    }

    @Test
    fun diskCache_persistsAcrossLoaderInstancesWithoutRefetching() = runTest {
        val diskDir = freshDiskCacheDir("disk-test")

        var firstFetchCount = 0
        val firstLoader = DefaultTHKImageLoader(context, diskCacheDir = diskDir, fetcher = { firstFetchCount++; testPng })
        assertThat(firstLoader.load("https://example.com/b.png")).isNotNull()
        assertThat(firstFetchCount).isEqualTo(1)

        // A fresh instance has an empty in-memory cache, but points at the same
        // on-disk cache dir, so it must be served from disk instead of re-fetching.
        var secondFetchCount = 0
        val secondLoader = DefaultTHKImageLoader(context, diskCacheDir = diskDir, fetcher = { secondFetchCount++; testPng })
        val bitmap2 = secondLoader.load("https://example.com/b.png")

        assertThat(bitmap2).isNotNull()
        assertThat(secondFetchCount).isEqualTo(0)
    }

    @Test
    fun differentUrls_areCachedIndependently() = runTest {
        var fetchCount = 0
        val loader = DefaultTHKImageLoader(
            context = context,
            diskCacheDir = freshDiskCacheDir("multi-url-test"),
            fetcher = { fetchCount++; testPng }
        )

        loader.load("https://example.com/one.png")
        loader.load("https://example.com/two.png")
        loader.load("https://example.com/one.png")

        assertThat(fetchCount).isEqualTo(2)
    }

    @Test
    fun fetchFailure_returnsNullAndIsNotCached() = runTest {
        var fetchCount = 0
        val loader = DefaultTHKImageLoader(
            context = context,
            diskCacheDir = freshDiskCacheDir("fail-test"),
            fetcher = { fetchCount++; null }
        )

        val result = loader.load("https://example.com/missing.png")

        assertThat(result).isNull()
        assertThat(fetchCount).isEqualTo(1)
    }

    @Test
    fun cancellingTheCallingCoroutine_stopsTheLoadInsteadOfResumingIt() = runTest {
        val fetchStarted = CompletableDeferred<Unit>()
        val neverResolves = CompletableDeferred<ByteArray?>()
        val loader = DefaultTHKImageLoader(
            context = context,
            diskCacheDir = freshDiskCacheDir("cancel-test"),
            fetcher = { fetchStarted.complete(Unit); neverResolves.await() }
        )

        val job = launch { loader.load("https://example.com/slow.png") }
        fetchStarted.await()
        job.cancel()
        job.join()

        assertThat(job.isCancelled).isTrue()
    }
}
