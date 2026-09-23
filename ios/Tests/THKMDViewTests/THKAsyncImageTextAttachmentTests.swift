import XCTest
@testable import THKMDView

private final class StubImageLoader: THKImageLoading {
    let image: UIImage?
    init(image: UIImage?) { self.image = image }
    func load(url: URL) async -> UIImage? { image }
}

private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1 // keeps `.size` in points equal to the requested pixel dimensions
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
    return renderer.image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

final class THKAsyncImageTextAttachmentTests: XCTestCase {
    @MainActor func testFormulaRequestsCoalesceAndCancellationDoesNotCancelOtherSubscriber() async {
        var requests: [[String: Any]] = []
        let engine = THKMathEngine(requestSink: { requests.append($0) })
        let url = URL(string: "thk-math://inline/eA")!
        let first = Task { await engine.render(url, theme: .default) }
        let second = Task { await engine.render(url, theme: .default) }
        for _ in 0..<100 {
            if engine.pendingSubscriberCount == 2 { break }
            await Task.yield()
        }
        guard engine.pendingSubscriberCount == 2 else {
            first.cancel(); second.cancel()
            return XCTFail("Subscriptions did not register")
        }
        XCTAssertEqual(requests.count, 1)
        first.cancel()
        let cancelled = await first.value
        XCTAssertNil(cancelled)
        let image = makeImage(width: 12, height: 12)
        guard let id = requests.first?["id"] as? String else { second.cancel(); return XCTFail("No request") }
        engine.finish(id, result: THKMathEngine.Result(image, descent: 0))
        let completed = await second.value
        XCTAssertNotNil(completed)
        let cached = await engine.render(url, theme: .default)
        XCTAssertNotNil(cached)
        XCTAssertEqual(requests.count, 1)
    }

    @MainActor func testPendingLoadDoesNotRetainDiscardedAttachment() async {
        final class SuspendedLoader: THKImageLoading {
            let started = XCTestExpectation(description: "load started")
            var continuation: CheckedContinuation<UIImage?, Never>?
            func load(url: URL) async -> UIImage? {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    started.fulfill()
                }
            }
        }
        let loader = SuspendedLoader()
        var attachment: THKAsyncImageTextAttachment? = makeAttachment()
        weak var weakAttachment = attachment
        attachment?.startLoading(imageLoader: loader, into: NSTextStorage())
        await fulfillment(of: [loader.started], timeout: 2)
        attachment = nil
        XCTAssertNil(weakAttachment)
        loader.continuation?.resume(returning: nil)
        loader.continuation = nil
    }

    private func makeAttachment() -> THKAsyncImageTextAttachment {
        THKAsyncImageTextAttachment(url: URL(string: "https://example.com/image.png")!, altText: "alt")
    }

    /// Before the real image loads, the box is a generic-aspect-ratio guess (0.6 height/width),
    /// not centered inside anything — its origin is always `.zero`.
    func testPlaceholderBoxBeforeLoad() {
        let attachment = makeAttachment()
        XCTAssertEqual(attachment.bounds.origin, .zero)
        XCTAssertEqual(attachment.bounds.size.width, THKAsyncImageTextAttachment.maxWidth)
        XCTAssertEqual(attachment.bounds.size.height, (THKAsyncImageTextAttachment.maxWidth * 0.6).rounded())
    }

    /// A wide image gets scaled down to maxWidth, height following the REAL aspect ratio (not a
    /// fixed placeholder height) — and the box stays flush at the origin, never centered inside
    /// a separately-sized reservation.
    func testWideImageScalesDownToMaxWidthPreservingRealAspectRatio() async {
        let attachment = makeAttachment()
        let textStorage = NSTextStorage(attributedString: NSAttributedString(attachment: attachment))
        let loader = StubImageLoader(image: makeImage(width: 400, height: 200))

        let sizeChanged = expectation(description: "onSizeChange fired")
        attachment.onSizeChange = { sizeChanged.fulfill() }
        attachment.startLoading(imageLoader: loader, into: textStorage)
        await fulfillment(of: [sizeChanged], timeout: 2.0)

        XCTAssertEqual(attachment.bounds.origin, .zero)
        XCTAssertEqual(attachment.bounds.size, CGSize(width: 240, height: 120))
    }

    /// An image smaller than maxWidth keeps its real (native) size — never upscaled to fill a
    /// larger reserved box.
    func testSmallImageIsNotUpscaled() async {
        let attachment = makeAttachment()
        let textStorage = NSTextStorage(attributedString: NSAttributedString(attachment: attachment))
        let loader = StubImageLoader(image: makeImage(width: 50, height: 50))

        let sizeChanged = expectation(description: "onSizeChange fired")
        attachment.onSizeChange = { sizeChanged.fulfill() }
        attachment.startLoading(imageLoader: loader, into: textStorage)
        await fulfillment(of: [sizeChanged], timeout: 2.0)

        XCTAssertEqual(attachment.bounds.size, CGSize(width: 50, height: 50))
    }

    /// An unusually tall/narrow image is clamped by the absolute maxHeight safety cap, with the
    /// width recomputed from that so the real aspect ratio is preserved (not squashed/stretched).
    func testTallNarrowImageIsCappedByMaxHeightPreservingAspectRatio() async {
        let attachment = makeAttachment()
        let textStorage = NSTextStorage(attributedString: NSAttributedString(attachment: attachment))
        let loader = StubImageLoader(image: makeImage(width: 10, height: 2000))

        let sizeChanged = expectation(description: "onSizeChange fired")
        attachment.onSizeChange = { sizeChanged.fulfill() }
        attachment.startLoading(imageLoader: loader, into: textStorage)
        await fulfillment(of: [sizeChanged], timeout: 2.0)

        XCTAssertEqual(attachment.bounds.size.height, THKAsyncImageTextAttachment.maxHeight)
        XCTAssertEqual(attachment.bounds.size.width, 2) // 320 * 10 / 2000, rounded
        XCTAssertEqual(attachment.bounds.origin, .zero)
    }
}
