package com.thk.mdview

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.text.Spanned
import android.text.method.LinkMovementMethod
import android.util.AttributeSet
import android.util.TypedValue
import android.view.View
import android.view.View.MeasureSpec
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
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
        for (i in 0 until childCount) {
            destroySegmentViewIfNeeded(getChildAt(i))
        }
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
                is RenderedSegment.DiagramSegment -> bindDiagramSegment(index, segment)
            }
            val child = getChildAt(index)
            val followsBlock = index > 0 && (getChildAt(index - 1) as? TextSegmentFrame)?.hasCopyGutter == true
            (child.layoutParams as LinearLayout.LayoutParams).topMargin =
                if (index > 0 && (followsBlock || (child as? TextSegmentFrame)?.hasCopyGutter == true))
                    (theme.bodyFontSizeSp * resources.displayMetrics.scaledDensity).toInt() else 0
        }
        while (childCount > segments.size) {
            destroySegmentViewIfNeeded(getChildAt(childCount - 1))
            removeViewAt(childCount - 1)
        }
    }

    private fun bindTextSegment(index: Int, segment: RenderedSegment.TextSegment) {
        val frame = reuseOrCreate(index) { createTextSegmentView() }
        val textView = frame.textView
        textView.setTextColor(theme.bodyTextColor)
        textView.setTextSize(TypedValue.COMPLEX_UNIT_SP, theme.bodyFontSizeSp)
        textView.text = segment.spanned

        val spanned = segment.spanned as? Spanned
        val quoteGutter = spanned?.getSpans(0, spanned.length, ThemedQuoteSpan::class.java)
            ?.maxOfOrNull { it.copyButtonGutterPx } ?: 0
        val codeGutter = spanned?.getSpans(0, spanned.length, CodeBlockBackgroundSpan::class.java)
            ?.maxOfOrNull { it.copyButtonGutterPx } ?: 0
        val lanes = segment.copyableBlocks.maxOfOrNull { block ->
            segment.copyableBlocks.count { block.range.first == it.range.first }
        } ?: 0
        val quotedCodeInset = if (quoteGutter > 0 && codeGutter > 0) dp(8f) else 0
        val gutter = maxOf(quoteGutter, codeGutter, if (lanes > 0) dp(36f * lanes + 4f) else 0) + quotedCodeInset
        spanned?.getSpans(0, spanned.length, CodeBlockBackgroundSpan::class.java)?.forEach {
            // Paint quoted code in the host so TextView's clip cannot cut off the copy lanes.
            it.drawsInHost = spanned.getSpans(0, spanned.length, ThemedQuoteSpan::class.java)
                .any { quote -> quote.containerBackground }
        }
        frame.isQuote = spanned?.getSpans(0, spanned.length, ThemedQuoteSpan::class.java)
            ?.any { it.containerBackground } == true
        val standaloneCode = spanned?.getSpans(0, spanned.length, CodeBlockBackgroundSpan::class.java)
            ?.any { it.containerBackground } == true
        val standalone = frame.isQuote || standaloneCode
        frame.hasCopyGutter = gutter > 0
        val verticalPadding = if (standalone) dp(8f) else 0
        textView.setPadding(0, verticalPadding, gutter, verticalPadding)
        textView.includeFontPadding = !frame.hasCopyGutter
        textView.setLineSpacing(if (frame.isQuote) 2 * resources.displayMetrics.density else 0f, 1f)
        frame.minimumHeight = if (frame.hasCopyGutter) dp(40f) else 0
        frame.background = if (standalone) GradientDrawable().apply {
            setColor(if (frame.isQuote) theme.blockQuoteBackgroundColor else theme.codeBackgroundColor)
            cornerRadius = theme.codeBlockCornerRadiusDp * resources.displayMetrics.density
        } else null
        val imageSpans = spanned?.getSpans(0, spanned.length, AsyncImageSpan::class.java).orEmpty()
        // A TextView can't expose distinct accessibility nodes per inline span without a
        // custom AccessibilityDelegate; as a pragmatic v1 stand-in, alt text becomes the
        // whole segment's content description whenever it contains at least one image.
        textView.contentDescription = imageSpans.takeIf { it.isNotEmpty() }?.joinToString(", ") { it.altText }
        for (span in imageSpans) {
            span.attach(imageLoader, imageLoadScope, textView)
            activeImageSpans += span
        }

        frame.updateCopyButtons(segment.copyableBlocks, theme, ::copyToClipboard)
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
        (listOf(segment.table.headerRow) + segment.table.bodyRows).forEachIndexed { row, cells ->
            cells.forEachIndexed cell@ { column, content ->
                val host = tableView.cellViewAt(row, column) ?: return@cell
                val text = content as? Spanned ?: return@cell
                text.getSpans(0, text.length, AsyncImageSpan::class.java).forEach { span ->
                    span.attach(imageLoader, imageLoadScope, host)
                    activeImageSpans += span
                }
            }
        }
    }

    private fun bindDiagramSegment(index: Int, segment: RenderedSegment.DiagramSegment) {
        // Width MATCH_PARENT caps the WebView to the bubble's width, same as THKTableView
        // above; the diagram template's own CSS (`max-width: 100%`) scales the rendered
        // SVG down to fit that width rather than overflowing it.
        val diagramView = reuseOrCreate(index) {
            THKMermaidView(context).apply {
                layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            }
        }
        diagramView.render(segment.mermaidSource, theme)
    }

    private inline fun <reified T : View> reuseOrCreate(index: Int, create: () -> T): T {
        val existing = getChildAt(index)
        if (existing is T) return existing
        if (index < childCount) {
            destroySegmentViewIfNeeded(getChildAt(index))
            removeViewAt(index)
        }
        val view = create()
        addView(view, index)
        return view
    }

    // WebViews are relatively heavy and must never leak across RecyclerView recycling -
    // called both when reset() tears everything down and when reuseOrCreate/applySegments
    // replace or drop a segment view of a different or now-absent type.
    private fun destroySegmentViewIfNeeded(view: View?) {
        if (view is THKMermaidView) view.destroy()
    }

    private fun createTextSegmentView(): TextSegmentFrame = TextSegmentFrame(context)

    private fun copyToClipboard(text: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboard?.setPrimaryClip(ClipData.newPlainText("code", text))
        Toast.makeText(context, R.string.thkmdview_copied, Toast.LENGTH_SHORT).show()
    }

    private fun dp(value: Float): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val NO_MAX_WIDTH = -1
        private const val MAX_IMAGE_WIDTH_DP = 240f
        // Absolute cap only kicks in for unusually tall/narrow images - most images are
        // sized by MAX_IMAGE_WIDTH_DP + their own real aspect ratio (see AsyncImageSpan).
        private const val MAX_IMAGE_HEIGHT_DP = 320f
        private const val MIN_IMAGE_WIDTH_DP = 80f
    }
}

// Wraps the text segment's TextView in a FrameLayout so a code block/outermost block
// quote's corner copy button can be a real, independently hit-testable child View - a
// Span only paints into the TextView's own canvas and isn't separately tappable, the
// same reasoning that gave tables their own THKTableView (see RESEARCH.md §8/§9).
// Top-level + internal (rather than private-nested in THKMDView) so THKMDViewReuseTest
// can assert against it directly, like it already does for THKTableView.
internal class TextSegmentFrame(context: Context) : FrameLayout(context) {
    var isQuote = false
    var hasCopyGutter = false
    val textView: AppCompatTextView = AppCompatTextView(context).apply {
        movementMethod = LinkMovementMethod.getInstance()
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
    }
    private val copyButtons = mutableListOf<ImageButton>()
    private var copyBlocks: List<CopyableBlock> = emptyList()

    init {
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        addView(textView)
    }

    fun updateCopyButtons(blocks: List<CopyableBlock>, theme: THKMDTheme, onCopy: (String) -> Unit) {
        copyButtons.forEach { removeView(it) }
        copyButtons.clear()
        // Place the enclosing/earlier block first, matching iOS. Otherwise a
        // recursively collected child code block pushes its parent button left.
        copyBlocks = blocks.sortedWith(compareBy<CopyableBlock> { it.range.first }.thenByDescending { it.range.last })
        val sizePx = (COPY_BUTTON_SIZE_DP * resources.displayMetrics.density).toInt()
        for (block in copyBlocks) {
            val button = createCopyButton(context, theme) { onCopy(block.text) }
            addView(button, LayoutParams(sizePx, sizePx))
            copyButtons += button
        }
        requestLayout()
    }

    override fun dispatchDraw(canvas: android.graphics.Canvas) {
        val layout = textView.layout
        val text = textView.text as? Spanned
        if (layout != null && text != null) {
            text.getSpans(0, text.length, CodeBlockBackgroundSpan::class.java)
                .filter { it.drawsInHost && !it.containerBackground }.forEach { span ->
                    val start = text.getSpanStart(span)
                    val end = text.getSpanEnd(span)
                    val first = layout.getLineForOffset(start)
                    val last = layout.getLineForOffset((end - 1).coerceAtLeast(start))
                    val indent = text.getSpans(start, start + 1, android.text.style.LeadingMarginSpan::class.java)
                        .filterNot { it is CodeBlockPaddingSpan }.sumOf { it.getLeadingMargin(true) }
                    val rect = android.graphics.RectF(
                        (textView.left + textView.paddingLeft + indent).toFloat(),
                        (textView.top + textView.paddingTop + layout.getLineTop(first)).toFloat(),
                        textView.right.toFloat() - 8 * resources.displayMetrics.density,
                        (textView.top + textView.paddingTop + layout.getLineBottom(last)).toFloat()
                    )
                    val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = span.backgroundColor }
                    canvas.drawRoundRect(rect, span.cornerRadiusPx, span.cornerRadiusPx, paint)
                }
        }
        super.dispatchDraw(canvas)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val layout = textView.layout ?: return
        val density = resources.displayMetrics.density
        val sizePx = (COPY_BUTTON_SIZE_DP * density).toInt()
        val marginPx = (COPY_BUTTON_MARGIN_DP * density).toInt()
        val positioned = mutableListOf<android.graphics.Rect>()
        copyButtons.zip(copyBlocks).forEach { (button, block) ->
            val offset = block.range.first.coerceIn(0, layout.text.length)
            val line = layout.getLineForOffset(offset)
            var x = (textView.right - sizePx - marginPx).coerceAtLeast(0)
            if (isQuote && copyBlocks.size > 1) x = (x - (8 * density).toInt()).coerceAtLeast(0)
            val y = textView.top + (if (hasCopyGutter && offset == 0) 0 else textView.paddingTop) +
                layout.getLineTop(line) + marginPx
            while (x > 0 && positioned.any { android.graphics.Rect.intersects(it, android.graphics.Rect(x, y, x + sizePx, y + sizePx)) }) {
                x = (x - sizePx - marginPx).coerceAtLeast(0)
            }
            positioned += android.graphics.Rect(x, y, x + sizePx, y + sizePx)
            button.layout(x, y, x + sizePx, y + sizePx)
        }
    }

    private companion object {
        const val COPY_BUTTON_SIZE_DP = 32f
        const val COPY_BUTTON_MARGIN_DP = 4f
    }
}

private fun createCopyButton(context: Context, theme: THKMDTheme, onClick: () -> Unit): ImageButton {
    val density = context.resources.displayMetrics.density
    val iconPaddingPx = (8 * density).toInt()
    val button = ImageButton(context)
    button.scaleType = ImageView.ScaleType.FIT_CENTER
    button.setPadding(iconPaddingPx, iconPaddingPx, iconPaddingPx, iconPaddingPx)
    button.background = rippleBackground(context)
    button.contentDescription = context.getString(R.string.thkmdview_copy_content_description)
    val icon: Drawable? = ContextCompat.getDrawable(context, R.drawable.ic_copy)?.mutate()
    icon?.let { DrawableCompat.setTint(it, theme.codeTextColor) }
    button.setImageDrawable(icon)
    button.setOnClickListener { onClick() }
    return button
}

// android.R.attr.selectableItemBackgroundBorderless: a themed circular ripple with no
// background fill outside the touch/press state, resolved at runtime (rather than
// hardcoded) so a copy button follows the host app's theme like everything else.
private fun rippleBackground(context: Context): Drawable? {
    val typedValue = TypedValue()
    val resolved = context.theme.resolveAttribute(
        android.R.attr.selectableItemBackgroundBorderless, typedValue, true
    )
    return if (resolved) ContextCompat.getDrawable(context, typedValue.resourceId) else null
}
