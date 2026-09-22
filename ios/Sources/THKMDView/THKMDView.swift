import UIKit

/// A container view rendering Markdown, including SSE-style streaming updates, as an ordered
/// vertical stack of segments: non-table blocks merge into one non-scrolling, non-editable
/// `UITextView` per run (as in v0), and each GFM table gets its own horizontally scrollable
/// `THKTableView`. Pin/size it like any auto-sizing view (it grows with its content via
/// `intrinsicContentSize`), and call `reset()` from `prepareForReuse`.
public final class THKMDView: UIView {
    public var streamingDebounceInterval: TimeInterval {
        get { buffer.debounceInterval }
        set { buffer.debounceInterval = newValue }
    }

    public var onLinkTap: ((URL) -> Bool)?
    public var onImageTap: ((URL) -> Bool)?

    public var renderer: MarkdownRendering = DefaultMarkdownRenderer() {
        didSet {
            renderer.theme = theme
            rerenderCurrentBuffer()
        }
    }

    public var imageLoader: THKImageLoading = DefaultTHKImageLoader()

    public var theme: THKMDTheme = .default {
        didSet {
            renderer.theme = theme
            rerenderCurrentBuffer()
        }
    }

    private let stack = UIStackView()
    private let buffer = StreamingMarkdownBuffer()
    private var segmentViews: [SegmentView] = []

    private final class TextSegmentView {
        let textView: UITextView
        let layoutManager: THKBackgroundLayoutManager
        var attachments: [THKAsyncImageTextAttachment] = []

        init(textView: UITextView, layoutManager: THKBackgroundLayoutManager) {
            self.textView = textView
            self.layoutManager = layoutManager
        }
    }

    private enum SegmentView {
        case text(TextSegmentView)
        case table(THKTableView)

        var view: UIView {
            switch self {
            case .text(let segment): return segment.textView
            case .table(let tableView): return tableView
            }
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        renderer.theme = theme

        buffer.onRender = { [weak self] text in
            self?.applyRenderedText(text)
        }
    }

    /// Full replace: renders immediately, bypassing the debounce (this is not a stream chunk).
    public func setMarkdown(_ markdown: String) {
        buffer.setFull(markdown)
    }

    /// Appends to the internal streaming buffer and schedules a debounced re-render of the
    /// whole buffer. Multiple chunks inside one debounce window coalesce into one render.
    public func appendMarkdownChunk(_ chunk: String) {
        buffer.append(chunk)
    }

    /// Clears the buffer, cancels any pending debounced render, and cancels every in-flight
    /// image load in every current segment. Must be safe to call from
    /// `prepareForReuse`/`onViewRecycled`, since none of that recycled-away work may ever land
    /// on the view after it's rebound to a new message.
    public func reset() {
        buffer.reset()
        for segmentView in segmentViews {
            removeFromStack(segmentView)
        }
        segmentViews = []
        invalidateIntrinsicContentSize()
    }

    private func applyRenderedText(_ markdown: String) {
        let segments = renderer.render(markdown)
        rebuild(with: segments)
        invalidateIntrinsicContentSize()
    }

    private func rerenderCurrentBuffer() {
        guard !buffer.text.isEmpty else { return }
        applyRenderedText(buffer.text)
    }

    // Reuses an existing arranged subview at the same index when its segment kind matches
    // (text-for-text, table-for-table), rather than always tearing down and rebuilding every
    // view. Exact minimal diffing isn't attempted — a kind mismatch at an index just replaces
    // that one view.
    private func rebuild(with segments: [THKRenderSegment]) {
        var newSegmentViews: [SegmentView] = []
        newSegmentViews.reserveCapacity(segments.count)

        for (index, segment) in segments.enumerated() {
            let existing = index < segmentViews.count ? segmentViews[index] : nil

            switch segment {
            case .text(let attributed):
                let segmentView: TextSegmentView
                if case .text(let reused)? = existing {
                    segmentView = reused
                } else {
                    if let existing { removeFromStack(existing) }
                    segmentView = makeTextSegmentView()
                    stack.insertArrangedSubview(segmentView.textView, at: index)
                }
                applyTheme(to: segmentView.layoutManager)
                segmentView.attachments.forEach { $0.cancelLoading() }
                segmentView.textView.attributedText = attributed
                segmentView.attachments = startImageLoads(in: attributed, textStorage: segmentView.textView.textStorage)
                newSegmentViews.append(.text(segmentView))

            case .table(let model):
                let tableView: THKTableView
                if case .table(let reused)? = existing {
                    tableView = reused
                } else {
                    if let existing { removeFromStack(existing) }
                    tableView = THKTableView()
                    stack.insertArrangedSubview(tableView, at: index)
                }
                tableView.configure(model: model, theme: theme)
                newSegmentViews.append(.table(tableView))
            }
        }

        if segmentViews.count > segments.count {
            for extra in segmentViews[segments.count...] {
                removeFromStack(extra)
            }
        }

        segmentViews = newSegmentViews
    }

    private func removeFromStack(_ segmentView: SegmentView) {
        if case .text(let segment) = segmentView {
            segment.attachments.forEach { $0.cancelLoading() }
        }
        let view = segmentView.view
        stack.removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    private func makeTextSegmentView() -> TextSegmentView {
        let (textView, layoutManager) = Self.makeTextView()
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        return TextSegmentView(textView: textView, layoutManager: layoutManager)
    }

    private static func makeTextView() -> (UITextView, THKBackgroundLayoutManager) {
        let textStorage = NSTextStorage()
        let layoutManager = THKBackgroundLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        let textView = UITextView(frame: .zero, textContainer: textContainer)
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.dataDetectorTypes = []
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        return (textView, layoutManager)
    }

    private func applyTheme(to layoutManager: THKBackgroundLayoutManager) {
        layoutManager.codeBlockBackgroundColor = theme.codeBackgroundColor
        layoutManager.inlineCodeBackgroundColor = theme.codeBackgroundColor
        layoutManager.blockQuoteBarColor = theme.blockQuoteBarColor
        layoutManager.codeBlockCornerRadius = theme.codeBlockCornerRadius
    }

    private func startImageLoads(in attributed: NSAttributedString, textStorage: NSTextStorage) -> [THKAsyncImageTextAttachment] {
        var attachments: [THKAsyncImageTextAttachment] = []
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let attachment = value as? THKAsyncImageTextAttachment {
                attachments.append(attachment)
            }
        }
        for attachment in attachments {
            attachment.startLoading(imageLoader: imageLoader, into: textStorage)
        }
        return attachments
    }

    public override var intrinsicContentSize: CGSize {
        let targetWidth = bounds.width > 0 ? bounds.width : UIView.layoutFittingCompressedSize.width
        let fitting = stack.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: fitting.height)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

extension THKMDView: UITextViewDelegate {
    public func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        onLinkTap?(URL) ?? true
    }

    public func textView(
        _ textView: UITextView,
        shouldInteractWith textAttachment: NSTextAttachment,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        guard let imageAttachment = textAttachment as? THKAsyncImageTextAttachment else { return true }
        return onImageTap?(imageAttachment.url) ?? true
    }
}
