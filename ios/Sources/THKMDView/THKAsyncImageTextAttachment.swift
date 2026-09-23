import UIKit

/// An `NSTextAttachment` that starts out as a generic-aspect-ratio placeholder box, then
/// re-sizes itself to the image's REAL aspect ratio once `imageLoader` resolves it — bounds
/// always exactly match the displayed size (never a wider reserved box with the image floating
/// centered inside it), so the image sits flush at the paragraph's left edge. Swapping in the
/// real image changes the attachment's `bounds`, which is a genuine layout change (glyph
/// geometry, not just pixels), so beyond `NSTextStorage.edited(.editedAttributes, ...)` (for
/// redrawing) `applyLoadedImage` also calls `invalidateLayout(forCharacterRange:...)` on every
/// attached layout manager to force TextKit to actually re-measure the line.
public final class THKAsyncImageTextAttachment: NSTextAttachment {
    /// Width cap once the real image is known; also the placeholder's width. Matches the
    /// existing "available max width" used elsewhere for image layout.
    public static let maxWidth: CGFloat = 240
    /// Absolute height safety cap (matches Android's `MAX_IMAGE_HEIGHT_DP`) so an unusually
    /// tall/narrow image can't blow out the message bubble's height.
    public static let maxHeight: CGFloat = 320
    /// height/width guess for the placeholder box shown before the real image loads, when the
    /// real aspect ratio isn't known yet.
    private static let placeholderAspectRatio: CGFloat = 0.6

    public let url: URL
    private let altText: String
    private weak var textStorage: NSTextStorage?
    private var loadTask: Task<Void, Never>?
    /// Set by `THKMDView` so a growing/shrinking image can tell the containing view's own
    /// intrinsic content size is stale too — `invalidateLayout` alone only tells TextKit to
    /// re-measure the text view's internal layout, not the Auto Layout constraints above it.
    public var onSizeChange: (() -> Void)?

    public init(url: URL, altText: String, theme: THKMDTheme = .default) {
        self.url = url
        self.altText = altText
        super.init(data: nil, ofType: nil)
        let placeholderSize = Self.placeholderSize()
        self.image = Self.placeholderImage(size: placeholderSize, color: theme.imagePlaceholderColor)
        self.bounds = CGRect(origin: .zero, size: placeholderSize)
        self.accessibilityLabel = altText
    }

    public required init?(coder: NSCoder) {
        fatalError("THKAsyncImageTextAttachment does not support NSCoding")
    }

    /// Called by `THKMDView` once the attachment's attributed string has been assigned to a
    /// text view's `NSTextStorage`. Cancelling a previous in-flight load (e.g. a rebuild that
    /// reuses this attachment) is safe to call more than once.
    public func startLoading(imageLoader: THKImageLoading, into textStorage: NSTextStorage) {
        self.textStorage = textStorage
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            guard let loaded = await imageLoader.load(url: self.url) else { return }
            if Task.isCancelled { return }
            await self.applyLoadedImage(loaded)
        }
    }

    /// Must be called before the attachment (or its owning text segment) is discarded — a
    /// recycled-away view's in-flight image load must never paint onto its replacement, the
    /// same reuse-safety guarantee `StreamingMarkdownBuffer`/`THKMDView.reset()` provide for
    /// streamed text.
    public func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }

    @MainActor
    private func applyLoadedImage(_ loadedImage: UIImage) {
        let fitted = Self.scaledSize(for: loadedImage.size)
        image = loadedImage
        bounds = CGRect(origin: .zero, size: fitted)

        guard let textStorage, let range = attachmentRange(in: textStorage) else { return }
        textStorage.beginEditing()
        textStorage.edited(.editedAttributes, range: range, changeInLength: 0)
        textStorage.endEditing()
        // .editedAttributes alone tells TextKit this range may need redrawing, but the
        // attachment object itself didn't change (only its `bounds` property did), so that
        // alone isn't guaranteed to make the layout manager re-measure the line's glyph
        // geometry — invalidateLayout explicitly forces the real re-layout the size change
        // needs (a placeholder-sized line growing/shrinking to the real image's box).
        for layoutManager in textStorage.layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }
        onSizeChange?()
    }

    private func attachmentRange(in textStorage: NSTextStorage) -> NSRange? {
        var found: NSRange?
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, range, stop in
            if let attachment = value as? THKAsyncImageTextAttachment, attachment === self {
                found = range
                stop.pointee = true
            }
        }
        return found
    }

    // Real aspect ratio, never upscaled past the source size: width is capped at maxWidth
    // (not stretched up to it), height follows from the real aspect ratio, and only an
    // unusually tall/narrow image gets clamped further by maxHeight (recomputing width from
    // that so the aspect ratio stays correct rather than squashing/stretching the image).
    private static func scaledSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return placeholderSize() }
        var width = min(size.width, maxWidth)
        var height = width * size.height / size.width
        if height > maxHeight {
            height = maxHeight
            width = height * size.width / size.height
        }
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    private static func placeholderSize() -> CGSize {
        CGSize(width: maxWidth, height: (maxWidth * placeholderAspectRatio).rounded())
    }

    private static func placeholderImage(size: CGSize, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12)
            color.setFill()
            path.fill()
        }
    }
}
