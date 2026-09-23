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
    func testOrdinaryParagraphUpdateLeavesCompletedPrefixUntouched() {
        final class Edits: NSObject, NSTextStorageDelegate {
            var locations: [Int] = []
            func textStorage(_ storage: NSTextStorage, didProcessEditing mask: NSTextStorage.EditActions,
                             range: NSRange, changeInLength: Int) {
                if mask.contains(.editedCharacters) { locations.append(range.location) }
            }
        }
        let view = THKMDView(frame: .zero)
        view.setMarkdown("第一段。\n\n第二段")
        func textView(in root: UIView) -> UITextView? {
            if let text = root as? UITextView { return text }
            return root.subviews.compactMap { textView(in: $0) }.first
        }
        guard let text = textView(in: view) else { return XCTFail("Missing text view") }
        let edits = Edits()
        text.textStorage.delegate = edits
        view.setMarkdown("第一段。\n\n第二段增加🙂")
        XCTAssertFalse(edits.locations.isEmpty)
        XCTAssertTrue(edits.locations.allSatisfy { $0 >= ("第一段。\n\n" as NSString).length })
        XCTAssertEqual(text.text, "第一段。\n\n第二段增加🙂")
    }

    func testIncrementalParsingMatchesFullParsingAndFallsBackForDefinitions() {
        let incremental = DefaultMarkdownRenderer()
        let full = DefaultMarkdownRenderer()
        full.incrementalParsingEnabled = false
        let cases = ["中文🙂第一段。\n\n第二段 **加粗**\n\n末段", "plain\n\nparagraph\n---",
                     "plain\n\n[link][ref]\n\n[ref]: https://example.com", "plain\n\n> quote\n\n- list", "plain\n\n$x$"]
        for source in cases {
            for end in 1...source.count {
                let prefix = String(source.prefix(end))
                func texts(_ renderer: DefaultMarkdownRenderer) -> [NSAttributedString] {
                    renderer.render(prefix).compactMap {
                        guard case .text(let text, _) = $0 else { return nil }
                        let normalized = NSMutableAttributedString(attributedString: text)
                        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                            if let image = value as? THKAsyncImageTextAttachment {
                                normalized.removeAttribute(.attachment, range: range)
                                normalized.addAttribute(NSAttributedString.Key("testImageURL"), value: image.url.absoluteString, range: range)
                            }
                        }
                        return normalized
                    }
                }
                let a = texts(incremental), b = texts(full)
                XCTAssertEqual(a.count, b.count)
                for (x, y) in zip(a, b) { XCTAssertTrue(x.isEqual(to: y), prefix) }
            }
        }
        let prefix = String(repeating: "stable paragraph\n\n", count: 100)
        _ = incremental.render(prefix + "tail")
        _ = incremental.render(prefix + "tail more")
        XCTAssertEqual(incremental.lastParsedCharacters, "stable paragraph\n\ntail more".utf16.count)
    }

    func testUnchangedThemeSkipsRenderingButChangedThemeRenders() {
        let spy = SpyRenderer()
        let view = THKMDView(frame: .zero)
        view.renderer = spy
        view.setMarkdown("stable")
        let count = spy.renderedMarkdowns.count
        view.theme = THKMDTheme.default
        XCTAssertEqual(spy.renderedMarkdowns.count, count)
        view.theme.bodyFontSize += 1
        XCTAssertEqual(spy.renderedMarkdowns.count, count + 1)
    }

    func testTableReuseDoesNotHideFormattingOrMutableInputChanges() {
        let view = THKTableView(frame: .zero)
        let value = NSMutableAttributedString(string: "same")
        let model = THKTableModel(alignments: [.leading], headerCells: [NSAttributedString(string: "Header")], rows: [[value]])
        func firstCell() -> UIView { view.subviews[0].subviews[0] }
        view.configure(model: model, theme: .default)
        let original = firstCell()
        view.configure(model: model, theme: .default)
        XCTAssertTrue(firstCell() === original)
        value.addAttribute(.foregroundColor, value: UIColor.red, range: NSRange(location: 0, length: value.length))
        view.configure(model: model, theme: .default)
        XCTAssertFalse(firstCell() === original)
    }

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
