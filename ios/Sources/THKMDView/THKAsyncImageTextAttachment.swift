import UIKit

/// An `NSTextAttachment` that starts out as a placeholder box sized to `maxSize`, then swaps
/// in the real image once `imageLoader` resolves it — without re-setting the containing text
/// view's `attributedText` or relayouting the surrounding text. The standard TextKit technique
/// for that is `NSTextStorage.edited(.editedAttributes, range:, changeInLength: 0)` on just the
/// attachment's character range, which is what `applyLoadedImage` does.
public final class THKAsyncImageTextAttachment: NSTextAttachment {
    public static let maxSize = CGSize(width: 240, height: 180)

    public let url: URL
    private let altText: String
    private weak var textStorage: NSTextStorage?
    private var loadTask: Task<Void, Never>?

    public init(url: URL, altText: String) {
        self.url = url
        self.altText = altText
        super.init(data: nil, ofType: nil)
        self.image = Self.placeholderImage(size: Self.maxSize)
        self.bounds = CGRect(origin: .zero, size: Self.maxSize)
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
        let fitted = Self.scaledSize(for: loadedImage.size, maxSize: Self.maxSize)
        image = loadedImage
        bounds = CGRect(origin: .zero, size: fitted)

        guard let textStorage, let range = attachmentRange(in: textStorage) else { return }
        textStorage.beginEditing()
        textStorage.edited(.editedAttributes, range: range, changeInLength: 0)
        textStorage.endEditing()
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

    private static func scaledSize(for size: CGSize, maxSize: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return maxSize }
        let scale = min(maxSize.width / size.width, maxSize.height / size.height, 1)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private static func placeholderImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12)
            UIColor.systemGray5.setFill()
            path.fill()
        }
    }
}
