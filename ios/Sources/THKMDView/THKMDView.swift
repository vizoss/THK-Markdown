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
            backgroundColor = theme.backgroundColor
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
        /// Current copy-button-eligible ranges for this segment's `attributedText`, and the
        /// overlay button placed for each — rebuilt whenever the segment's content is rebuilt
        /// (see `rebuildCopyButtons`), repositioned on every `layoutSubviews` (see
        /// `positionCopyButtons`) since the text view's real width/line layout isn't settled
        /// until Auto Layout has run.
        var copyableBlocks: [THKCopyableBlock] = []
        var copyButtons: [(button: UIButton, block: THKCopyableBlock)] = []

        init(textView: UITextView, layoutManager: THKBackgroundLayoutManager) {
            self.textView = textView
            self.layoutManager = layoutManager
        }
    }

    private enum SegmentView {
        case text(TextSegmentView)
        case table(THKTableView)
        case diagram(THKMermaidView)

        var view: UIView {
            switch self {
            case .text(let segment): return segment.textView
            case .table(let tableView): return tableView
            case .diagram(let mermaidView): return mermaidView
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
        backgroundColor = theme.backgroundColor

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
            case .text(let attributed, let copyableBlocks):
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
                segmentView.attachments = startImageLoads(in: attributed, into: segmentView.textView)
                segmentView.copyableBlocks = copyableBlocks
                rebuildCopyButtons(for: segmentView)
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

            case .diagram(let mermaidSource):
                let mermaidView: THKMermaidView
                if case .diagram(let reused)? = existing {
                    mermaidView = reused
                } else {
                    if let existing { removeFromStack(existing) }
                    mermaidView = THKMermaidView()
                    mermaidView.translatesAutoresizingMaskIntoConstraints = false
                    mermaidView.onSizeChange = { [weak self, weak mermaidView] in
                        mermaidView?.invalidateIntrinsicContentSize()
                        self?.invalidateIntrinsicContentSize()
                    }
                    stack.insertArrangedSubview(mermaidView, at: index)
                }
                mermaidView.configure(source: mermaidSource, theme: theme)
                newSegmentViews.append(.diagram(mermaidView))
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
        switch segmentView {
        case .text(let segment):
            segment.attachments.forEach { $0.cancelLoading() }
            segment.copyButtons.forEach { $0.button.removeFromSuperview() }
            segment.copyButtons = []
        case .diagram(let mermaidView):
            mermaidView.stop()
        case .table:
            break
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
        layoutManager.blockQuoteBackgroundColor = theme.blockQuoteBackgroundColor
        layoutManager.codeBlockCornerRadius = theme.codeBlockCornerRadius
        layoutManager.thematicBreakColor = theme.tableBorderColor
    }

    // MARK: - Copy buttons (code blocks + outermost block quotes)

    private func rebuildCopyButtons(for segmentView: TextSegmentView) {
        segmentView.copyButtons.forEach { $0.button.removeFromSuperview() }
        segmentView.copyButtons = segmentView.copyableBlocks.map { block in
            let button = makeCopyButton()
            segmentView.textView.addSubview(button)
            return (button, block)
        }
        positionCopyButtons(for: segmentView)
    }

    // Re-run on every `layoutSubviews` (not only when a segment's content is rebuilt): the
    // text view's real width/line layout isn't settled at `rebuild(with:)` time when this is a
    // freshly bound cell, so the first positioning pass can be based on a stale/zero width.
    private func positionCopyButtons(for segmentView: TextSegmentView) {
        let textView = segmentView.textView
        let layoutManager = textView.layoutManager
        let storageLength = textView.textStorage.length
        for (button, block) in segmentView.copyButtons {
            guard block.range.location != NSNotFound, NSMaxRange(block.range) <= storageLength, block.range.length > 0 else {
                button.isHidden = true
                continue
            }
            button.isHidden = false
            let glyphRange = layoutManager.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let size = THKCopyButtonMetrics.size
            let margin = THKCopyButtonMetrics.margin
            let x = min(firstLineRect.maxX, textView.bounds.width) - size - margin
            let y = firstLineRect.minY + margin
            button.frame = CGRect(x: max(0, x), y: max(0, y), width: size, height: size)
        }
    }

    // Drawn programmatically (Lucide's "copy" icon, ISC license) instead of the SF Symbol
    // `doc.on.doc`, to match Android's copy-button icon exactly rather than landing on a
    // different-looking system glyph. Built once and cached rather than bundling an image
    // asset, which would need separate SPM/CocoaPods resource wiring for one small icon.
    private static let copyIconImage: UIImage = makeCopyIconImage()

    private static func makeCopyIconImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { _ in
            let path = UIBezierPath()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // Front sheet: the SVG's `<rect width="14" height="14" x="8" y="8" rx="2" ry="2" />`.
            path.append(UIBezierPath(roundedRect: CGRect(x: 8, y: 8, width: 14, height: 14), cornerRadius: 2))

            // Back sheet: an open outline (no right/bottom edge — those are hidden behind the
            // front sheet), translating the SVG `<path>`'s relative cubic-Bézier ("c") commands
            // directly into addCurve calls: "M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2".
            let back = UIBezierPath()
            back.move(to: CGPoint(x: 4, y: 16))
            back.addCurve(to: CGPoint(x: 2, y: 14), controlPoint1: CGPoint(x: 2.9, y: 16), controlPoint2: CGPoint(x: 2, y: 15.1))
            back.addLine(to: CGPoint(x: 2, y: 4))
            back.addCurve(to: CGPoint(x: 4, y: 2), controlPoint1: CGPoint(x: 2, y: 2.9), controlPoint2: CGPoint(x: 2.9, y: 2))
            back.addLine(to: CGPoint(x: 14, y: 2))
            back.addCurve(to: CGPoint(x: 16, y: 4), controlPoint1: CGPoint(x: 15.1, y: 2), controlPoint2: CGPoint(x: 16, y: 2.9))
            path.append(back)

            UIColor.black.setStroke()
            path.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private func makeCopyButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(Self.copyIconImage, for: .normal)
        button.tintColor = .secondaryLabel
        button.backgroundColor = .clear
        button.frame = CGRect(x: 0, y: 0, width: THKCopyButtonMetrics.size, height: THKCopyButtonMetrics.size)
        button.addTarget(self, action: #selector(copyButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func copyButtonTapped(_ sender: UIButton) {
        for segmentView in segmentViews {
            guard case .text(let segment) = segmentView else { continue }
            guard let match = segment.copyButtons.first(where: { $0.button === sender }) else { continue }
            UIPasteboard.general.string = match.block.text
            showCopyFeedback(near: sender, in: segment.textView)
            return
        }
    }

    // A brief, self-dismissing "Copied" label rather than a full toast framework — this
    // codebase has no existing toast mechanism, and this is a one-off, low-stakes affordance.
    private func showCopyFeedback(near button: UIButton, in textView: UITextView) {
        let label = UILabel()
        label.text = "Copied"
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.textAlignment = .center
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        label.alpha = 0
        let width: CGFloat = 64
        let height: CGFloat = 22
        label.frame = CGRect(x: button.frame.maxX - width, y: button.frame.maxY + 4, width: width, height: height)
        textView.addSubview(label)
        UIView.animate(withDuration: 0.15, animations: {
            label.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.2, delay: 0.6, options: [], animations: {
                label.alpha = 0
            }, completion: { _ in
                label.removeFromSuperview()
            })
        })
    }

    private func startImageLoads(in attributed: NSAttributedString, into textView: UITextView) -> [THKAsyncImageTextAttachment] {
        var attachments: [THKAsyncImageTextAttachment] = []
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if let attachment = value as? THKAsyncImageTextAttachment {
                attachments.append(attachment)
            }
        }
        for attachment in attachments {
            // The image's real size (once loaded) can differ from the placeholder box, which
            // changes this text view's own intrinsic content size, which in turn changes
            // THKMDView's (its stack view wraps this text view) — both need to be told their
            // previously-cached intrinsic size is stale, not just TextKit's internal layout.
            attachment.onSizeChange = { [weak self, weak textView] in
                textView?.invalidateIntrinsicContentSize()
                self?.invalidateIntrinsicContentSize()
            }
            attachment.startLoading(imageLoader: imageLoader, into: textView.textStorage)
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
        for segmentView in segmentViews {
            if case .text(let segment) = segmentView {
                positionCopyButtons(for: segment)
            }
        }
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
