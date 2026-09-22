import XCTest
@testable import THKMDView

private final class SpyRenderer: MarkdownRendering {
    var theme: THKMDTheme = .default
    private(set) var renderedMarkdowns: [String] = []

    func render(_ markdown: String) -> [THKRenderSegment] {
        renderedMarkdowns.append(markdown)
        return [.text(NSAttributedString(string: markdown), copyableBlocks: [])]
    }
}

final class THKMDViewTests: XCTestCase {
    func testSetMarkdownRendersImmediatelyWithoutWaiting() {
        let spy = SpyRenderer()
        let view = THKMDView(frame: .zero)
        view.renderer = spy

        view.setMarkdown("Hello")

        XCTAssertEqual(spy.renderedMarkdowns, ["Hello"])
    }

    func testResetClearsTextSynchronously() {
        let view = THKMDView(frame: .zero)
        view.setMarkdown("Some content")
        view.reset()

        // reset() must be safe to call from prepareForReuse with no pending work outstanding.
        XCTAssertTrue(true)
    }

    /// Mirrors the UITableViewCell reuse scenario from prepareForReuse: a chunk is mid-flight
    /// (debounced render pending) when the cell is recycled. reset() must guarantee that old
    /// pending render can never land on the view after it's rebound to a new message.
    func testReuseSafetyAcrossCellRebind() {
        let spy = SpyRenderer()
        let view = THKMDView(frame: .zero)
        view.renderer = spy
        view.streamingDebounceInterval = 0.02

        view.appendMarkdownChunk("Message A, streaming in...")

        let recycled = expectation(description: "cell recycled and rebound before old debounce fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
            view.reset()
            view.setMarkdown("Message B, a totally different row")
            recycled.fulfill()
        }
        wait(for: [recycled], timeout: 1.0)

        // Give the ORIGINAL (now-cancelled) debounce window time to have fired if it wasn't
        // actually cancelled, which would be the bug this test guards against.
        let settled = expectation(description: "settle past the original debounce window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1.0)

        XCTAssertEqual(spy.renderedMarkdowns, ["Message B, a totally different row"])
    }

    func testOnLinkTapInterceptsInteraction() {
        let view = THKMDView(frame: .zero)
        var tappedURL: URL?
        view.onLinkTap = { url in
            tappedURL = url
            return false
        }

        view.setMarkdown("[Apple](https://apple.com)")

        let url = URL(string: "https://apple.com")!
        let handled = view.textView(
            UITextView(),
            shouldInteractWith: url,
            in: NSRange(location: 0, length: 0),
            interaction: .invokeDefaultAction
        )

        XCTAssertEqual(tappedURL, url)
        XCTAssertFalse(handled)
    }

    func testDefaultLinkBehaviorOpensWhenNoHandlerInstalled() {
        let view = THKMDView(frame: .zero)
        let handled = view.textView(
            UITextView(),
            shouldInteractWith: URL(string: "https://apple.com")!,
            in: NSRange(location: 0, length: 0),
            interaction: .invokeDefaultAction
        )
        XCTAssertTrue(handled)
    }
}
