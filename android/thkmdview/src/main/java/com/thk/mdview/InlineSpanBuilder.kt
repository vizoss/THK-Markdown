package com.thk.mdview

import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import org.commonmark.ext.gfm.strikethrough.Strikethrough
import org.commonmark.node.AbstractVisitor
import org.commonmark.node.Code
import org.commonmark.node.CustomNode
import org.commonmark.node.Emphasis
import org.commonmark.node.HardLineBreak
import org.commonmark.node.HtmlInline
import org.commonmark.node.Image
import org.commonmark.node.Link
import org.commonmark.node.Node
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text

/** Bounds + styling an inline `![]()` image is built with. */
internal data class ImageRenderContext(
    val bounds: ImageBounds,
    val cornerRadiusPx: Float,
    val placeholderColor: Int,
    val clickHandler: (String) -> Boolean
)

/**
 * Converts a run of inline Markdown nodes (the content of a paragraph, heading, list
 * item, or GFM table cell) into spans appended onto [builder]. Extracted as a shared
 * entry point so table cells (THKTableView) and normal block flow (MarkdownSpanVisitor)
 * use identical bold/italic/code/link/strikethrough/image span logic instead of two
 * copies drifting apart.
 */
internal object InlineSpanBuilder {

    fun appendInline(
        node: Node?,
        builder: SpannableStringBuilder,
        theme: THKMDTheme,
        linkHandler: (String) -> Boolean,
        imageContext: ImageRenderContext
    ) {
        var child = node
        while (child != null) {
            appendNode(child, builder, theme, linkHandler, imageContext)
            child = child.next
        }
    }

    private fun appendNode(
        node: Node,
        builder: SpannableStringBuilder,
        theme: THKMDTheme,
        linkHandler: (String) -> Boolean,
        imageContext: ImageRenderContext
    ) {
        when (node) {
            is Text -> builder.append(node.literal)
            is HtmlInline -> builder.append(node.literal)
            is HardLineBreak -> builder.append('\n')
            is SoftLineBreak -> builder.append(' ')
            is Emphasis -> withSpan(builder, StyleSpan(Typeface.ITALIC)) {
                appendInline(node.firstChild, builder, theme, linkHandler, imageContext)
            }
            is StrongEmphasis -> withSpan(builder, StyleSpan(Typeface.BOLD)) {
                appendInline(node.firstChild, builder, theme, linkHandler, imageContext)
            }
            is Code -> appendCode(node.literal, builder, theme)
            is Link -> appendLink(node, builder, theme, linkHandler, imageContext)
            is Image -> appendImage(node, builder, imageContext)
            is CustomNode -> if (node is Strikethrough) {
                withSpan(builder, StrikethroughSpan()) {
                    appendInline(node.firstChild, builder, theme, linkHandler, imageContext)
                }
            } else {
                appendInline(node.firstChild, builder, theme, linkHandler, imageContext)
            }
            else -> appendInline(node.firstChild, builder, theme, linkHandler, imageContext)
        }
    }

    private fun appendCode(literal: String, builder: SpannableStringBuilder, theme: THKMDTheme) {
        val start = builder.length
        builder.append(literal)
        val end = builder.length
        if (end == start) return
        val sizeRatio = theme.codeFontSizeSp / theme.bodyFontSizeSp
        builder.setSpan(BackgroundColorSpan(theme.codeBackgroundColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(ForegroundColorSpan(theme.codeTextColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(TypefaceSpan("monospace"), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(RelativeSizeSpan(sizeRatio), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    private fun appendLink(
        link: Link,
        builder: SpannableStringBuilder,
        theme: THKMDTheme,
        linkHandler: (String) -> Boolean,
        imageContext: ImageRenderContext
    ) {
        val url = link.destination ?: ""
        val start = builder.length
        appendInline(link.firstChild, builder, theme, linkHandler, imageContext)
        val end = builder.length
        if (end == start) return
        builder.setSpan(LinkClickableSpan(url, linkHandler), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(ForegroundColorSpan(theme.linkColor), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    private fun appendImage(
        image: Image,
        builder: SpannableStringBuilder,
        imageContext: ImageRenderContext
    ) {
        val url = image.destination ?: ""
        val altText = plainTextOf(image)
        val span = AsyncImageSpan(
            url = url,
            altText = altText,
            maxWidthPx = imageContext.bounds.maxWidthPx,
            absoluteMaxHeightPx = imageContext.bounds.maxHeightPx,
            cornerRadiusPx = imageContext.cornerRadiusPx,
            placeholderColor = imageContext.placeholderColor
        )
        val start = builder.length
        // An image is an inline object, not whitespace. Android may omit trailing
        // spaces from line drawing while still reserving ReplacementSpan metrics.
        // U+FFFC keeps loading/failed images drawable at a wrap or paragraph end.
        builder.append('\uFFFC')
        val end = builder.length
        builder.setSpan(span, start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(LinkClickableSpan(url, imageContext.clickHandler), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    private fun plainTextOf(node: Node): String {
        val sb = StringBuilder()
        node.accept(object : AbstractVisitor() {
            override fun visit(text: Text) {
                sb.append(text.literal)
            }
        })
        return sb.toString()
    }

    private inline fun withSpan(builder: SpannableStringBuilder, span: Any, block: () -> Unit) {
        val start = builder.length
        block()
        val end = builder.length
        if (end > start) {
            builder.setSpan(span, start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }
}
