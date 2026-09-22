package com.thk.mdview

import android.content.Context
import android.text.Spanned
import android.text.method.LinkMovementMethod
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View
import android.view.View.MeasureSpec
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatTextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlin.math.min

/**
 * Renders streaming Markdown as a vertical sequence of segments (RESEARCH.md §9): most
 * messages render as exactly one internal text view, and any GFM table gets its own
 * [THKTableView] child so it can scroll horizontally on its own. No longer a `TextView`
 * subclass (breaking change from v0) - XML attributes like `android:textSize` set
 * directly on `<com.thk.mdview.THKMDView>` no longer apply; use [theme] instead.
 */
class THKMDView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    var streamingDebounceMs: Long = 32L
        set(value) {
            field = value
            buffer.debounceMs = value
        }

    var onLinkClick: ((String) -> Boolean)? = null

    /** Invoked when a rendered image is tapped; falls back to [onLinkClick] with the image URL if unset. */
    var onImageClick: ((String) -> Boolean)? = null

    var theme: THKMDTheme = THKMDTheme.Default
        set(value) {
            field = value
            setBackgroundColor(value.backgroundColor)
            renderNow(buffer.currentText)
        }

    var imageLoader: THKImageLoader = DefaultTHKImageLoader(context)

    /**
     * Caps this view's measured width (e.g. so a chat bubble doesn't stretch edge to
     * edge for a long unwrapped line), mirroring `TextView.maxWidth` - which THKMDView
     * lost by no longer being a `TextView`. `<= 0` (the default) means unconstrained.
     */
    var maxContentWidthPx: Int = NO_MAX_WIDTH

    private var renderer: MarkdownRenderer = DefaultMarkdownRenderer(
        context = context,
        linkHandler = { url -> onLinkClick?.invoke(url) == true },
        imageClickHandler = { url -> (onImageClick ?: onLinkClick)?.invoke(url) == true }
    )

    // Tied to this view (not any single segment) so reset()/onDetachedFromWindow cancel
    // every in-flight image load regardless of which segment view kicked it off.
    private val imageLoadScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val activeImageSpans = mutableListOf<AsyncImageSpan>()

    private val buffer = StreamingMarkdownBuffer(debounceMs = streamingDebounceMs) { markdown ->
        renderNow(markdown)
    }

    init {
        orientation = VERTICAL
        setBackgroundColor(theme.backgroundColor)
    }

    fun setMarkdown(markdown: String) {
        buffer.setFull(markdown)
    }

    fun appendMarkdownChunk(chunk: String) {
        buffer.append(chunk)
    }

    // Safe to call from onViewRecycled: cancels any pending debounced render and any
    // in-flight image loads - so neither a stale text render nor a stale image bitmap
    // from a recycled-away message can ever land on the view that replaced it - and
    // clears the segment child views.
    fun reset() {
        buffer.reset()
        cancelActiveImageLoads()
        removeAllViews()
    }

    fun setMarkdownRenderer(renderer: MarkdownRenderer) {
        this.renderer = renderer
        renderNow(buffer.currentText)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        cancelActiveImageLoads()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        var spec = widthMeasureSpec
        if (maxContentWidthPx > 0) {
            val mode = MeasureSpec.getMode(widthMeasureSpec)
            val size = MeasureSpec.getSize(widthMeasureSpec)
            val cappedSize = if (mode == MeasureSpec.UNSPECIFIED) maxContentWidthPx else min(size, maxContentWidthPx)
            val cappedMode = if (mode == MeasureSpec.EXACTLY) MeasureSpec.EXACTLY else MeasureSpec.AT_MOST
            spec = MeasureSpec.makeMeasureSpec(cappedSize, cappedMode)
        }
        super.onMeasure(spec, heightMeasureSpec)
    }

    private fun cancelActiveImageLoads() {
        activeImageSpans.forEach { it.cancel() }
        activeImageSpans.clear()
    }

    private fun renderNow(markdown: String) {
        cancelActiveImageLoads()
        val available = width - paddingLeft - paddingRight
        val maxImageWidthPx = (if (available > 0) min(dp(MAX_IMAGE_WIDTH_DP), available) else dp(MAX_IMAGE_WIDTH_DP))
            .coerceAtLeast(dp(MIN_IMAGE_WIDTH_DP))
        val bounds = ImageBounds(maxImageWidthPx, dp(MAX_IMAGE_HEIGHT_DP))
        val segments = renderer.render(markdown, theme, bounds)
        applySegments(segments)
    }

    private fun applySegments(segments: List<RenderedSegment>) {
        segments.forEachIndexed { index, segment ->
            when (segment) {
                is RenderedSegment.TextSegment -> bindTextSegment(index, segment)
                is RenderedSegment.TableSegment -> bindTableSegment(index, segment)
            }
        }
        while (childCount > segments.size) {
            removeViewAt(childCount - 1)
        }
    }

    private fun bindTextSegment(index: Int, segment: RenderedSegment.TextSegment) {
        val textView = reuseOrCreate(index) { createTextSegmentView() }
        textView.setTextColor(theme.bodyTextColor)
        textView.setTextSize(TypedValue.COMPLEX_UNIT_SP, theme.bodyFontSizeSp)
        textView.text = segment.spanned

        val spanned = segment.spanned as? Spanned
        val imageSpans = spanned?.getSpans(0, spanned.length, AsyncImageSpan::class.java).orEmpty()
        // A TextView can't expose distinct accessibility nodes per inline span without a
        // custom AccessibilityDelegate; as a pragmatic v1 stand-in, alt text becomes the
        // whole segment's content description whenever it contains at least one image.
        textView.contentDescription = imageSpans.takeIf { it.isNotEmpty() }?.joinToString(", ") { it.altText }
        for (span in imageSpans) {
            span.attach(imageLoader, imageLoadScope, textView)
            activeImageSpans += span
        }
    }

    private fun bindTableSegment(index: Int, segment: RenderedSegment.TableSegment) {
        // Width MATCH_PARENT caps THKTableView to the message bubble's width - its
        // internal HorizontalScrollView is what lets the (potentially wider) grid inside
        // scroll independently, instead of the table just stretching the whole bubble.
        val tableView = reuseOrCreate(index) {
            THKTableView(context).apply {
                layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            }
        }
        tableView.setData(segment.table, theme)
    }

    private inline fun <reified T : View> reuseOrCreate(index: Int, create: () -> T): T {
        val existing = getChildAt(index)
        if (existing is T) return existing
        val view = create()
        if (index < childCount) {
            removeViewAt(index)
        }
        addView(view, index)
        return view
    }

    private fun createTextSegmentView(): AppCompatTextView = AppCompatTextView(context).apply {
        movementMethod = LinkMovementMethod.getInstance()
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
    }

    private fun dp(value: Float): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val NO_MAX_WIDTH = -1
        private const val MAX_IMAGE_WIDTH_DP = 240f
        private const val MAX_IMAGE_HEIGHT_DP = 180f
        private const val MIN_IMAGE_WIDTH_DP = 80f
    }
}
