import UIKit

/// A UIView wrapping one non-scrolling, non-editable UITextView that renders Markdown,
/// including SSE-style streaming updates. Pin/size it like any auto-sizing view (it grows
/// with its text via `intrinsicContentSize`), and call `reset()` from `prepareForReuse`.
public final class THKMDView: UIView {
    public var streamingDebounceInterval: TimeInterval {
        get { buffer.debounceInterval }
        set { buffer.debounceInterval = newValue }
    }

    public var onLinkTap: ((URL) -> Bool)?

    public var renderer: MarkdownRendering = DefaultMarkdownRenderer() {
        didSet { rerenderCurrentBuffer() }
    }

    private let textView: UITextView
    private let layoutManager: THKBackgroundLayoutManager
    private let buffer = StreamingMarkdownBuffer()

    public override init(frame: CGRect) {
        (textView, layoutManager) = Self.makeTextView()
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        (textView, layoutManager) = Self.makeTextView()
        super.init(coder: coder)
        commonInit()
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
        return (textView, layoutManager)
    }

    private func commonInit() {
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.dataDetectorTypes = []
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

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

    /// Clears the buffer and cancels any pending debounced render. Must be safe to call from
    /// `prepareForReuse`/`onViewRecycled`, since a pending render from a recycled-away cell
    /// must never land on the view that replaced it.
    public func reset() {
        buffer.reset()
        textView.attributedText = NSAttributedString(string: "")
        invalidateIntrinsicContentSize()
    }

    private func applyRenderedText(_ markdown: String) {
        textView.attributedText = renderer.render(markdown)
        invalidateIntrinsicContentSize()
    }

    private func rerenderCurrentBuffer() {
        guard !buffer.text.isEmpty else { return }
        applyRenderedText(buffer.text)
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: textView.intrinsicContentSize.height)
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
}
