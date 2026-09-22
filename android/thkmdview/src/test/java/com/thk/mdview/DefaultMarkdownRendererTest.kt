package com.thk.mdview

import android.text.Spannable
import android.text.style.BackgroundColorSpan
import android.text.style.BulletSpan
import android.text.style.ClickableSpan
import android.text.style.LineBackgroundSpan
import android.text.style.QuoteSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DefaultMarkdownRendererTest {

    private val renderer = DefaultMarkdownRenderer()

    @Test
    fun bold() {
        val spanned = renderer.render("**bold**") as Spannable
        assertThat(spanned.toString()).isEqualTo("bold")
        val spans = spanned.getSpans(0, spanned.length, StyleSpan::class.java)
        assertThat(spans.any { it.style == android.graphics.Typeface.BOLD }).isTrue()
    }

    @Test
    fun italic() {
        val spanned = renderer.render("*italic*") as Spannable
        assertThat(spanned.toString()).isEqualTo("italic")
        val spans = spanned.getSpans(0, spanned.length, StyleSpan::class.java)
        assertThat(spans.any { it.style == android.graphics.Typeface.ITALIC }).isTrue()
    }

    @Test
    fun inlineCode() {
        val spanned = renderer.render("`code`") as Spannable
        assertThat(spanned.toString()).isEqualTo("code")
        assertThat(spanned.getSpans(0, spanned.length, TypefaceSpan::class.java)).isNotEmpty()
        assertThat(spanned.getSpans(0, spanned.length, BackgroundColorSpan::class.java)).isNotEmpty()
    }

    @Test
    fun heading() {
        val spanned = renderer.render("# Heading") as Spannable
        assertThat(spanned.toString()).isEqualTo("Heading")
        val sizeSpans = spanned.getSpans(0, spanned.length, RelativeSizeSpan::class.java)
        assertThat(sizeSpans).isNotEmpty()
        assertThat(sizeSpans[0].sizeChange).isGreaterThan(1.0f)
        val styleSpans = spanned.getSpans(0, spanned.length, StyleSpan::class.java)
        assertThat(styleSpans.any { it.style == android.graphics.Typeface.BOLD }).isTrue()
    }

    @Test
    fun headingLevelsScaleDown() {
        val h1 = renderer.render("# H1") as Spannable
        val h3 = renderer.render("### H3") as Spannable
        val h1Size = h1.getSpans(0, h1.length, RelativeSizeSpan::class.java).first().sizeChange
        val h3Size = h3.getSpans(0, h3.length, RelativeSizeSpan::class.java).first().sizeChange
        assertThat(h1Size).isGreaterThan(h3Size)
    }

    @Test
    fun link() {
        val spanned = renderer.render("[example](https://example.com)") as Spannable
        assertThat(spanned.toString()).isEqualTo("example")
        val spans = spanned.getSpans(0, spanned.length, ClickableSpan::class.java)
        assertThat(spans).hasLength(1)

        var clickedUrl: String? = null
        val testRenderer = DefaultMarkdownRenderer(linkHandler = { url ->
            clickedUrl = url
            true
        })
        val clickable = testRenderer.render("[example](https://example.com)") as Spannable
        val span = clickable.getSpans(0, clickable.length, ClickableSpan::class.java).first()
        span.onClick(android.view.View(androidx.test.core.app.ApplicationProvider.getApplicationContext()))
        assertThat(clickedUrl).isEqualTo("https://example.com")
    }

    @Test
    fun blockQuote() {
        val spanned = renderer.render("> quoted text") as Spannable
        assertThat(spanned.toString()).isEqualTo("quoted text")
        assertThat(spanned.getSpans(0, spanned.length, QuoteSpan::class.java)).isNotEmpty()
    }

    @Test
    fun codeBlock() {
        val spanned = renderer.render("```\nfun main() {}\n```") as Spannable
        assertThat(spanned.toString()).isEqualTo("fun main() {}")
        assertThat(spanned.getSpans(0, spanned.length, LineBackgroundSpan::class.java)).isNotEmpty()
        assertThat(spanned.getSpans(0, spanned.length, TypefaceSpan::class.java)).isNotEmpty()
    }

    @Test
    fun unorderedListItem() {
        val spanned = renderer.render("- item one") as Spannable
        assertThat(spanned.toString()).isEqualTo("item one")
        assertThat(spanned.getSpans(0, spanned.length, BulletSpan::class.java)).isNotEmpty()
    }

    @Test
    fun strikethrough() {
        val spanned = renderer.render("~~gone~~") as Spannable
        assertThat(spanned.toString()).isEqualTo("gone")
        assertThat(spanned.getSpans(0, spanned.length, StrikethroughSpan::class.java)).isNotEmpty()
    }

    @Test
    fun image_rendersAltTextOnly() {
        val spanned = renderer.render("![alt text](https://example.com/pic.png)") as Spannable
        assertThat(spanned.toString()).isEqualTo("alt text")
    }

    @Test
    fun table_fallsBackToPlainMonospaceRows() {
        val markdown = "| a | b |\n| --- | --- |\n| 1 | 2 |\n"
        val spanned = renderer.render(markdown) as Spannable
        assertThat(spanned.toString()).contains("a")
        assertThat(spanned.toString()).contains("1")
        assertThat(spanned.getSpans(0, spanned.length, TypefaceSpan::class.java)).isNotEmpty()
    }
}
