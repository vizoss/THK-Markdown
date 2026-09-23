import XCTest
import UIKit
@testable import THKMDView
#if canImport(MarkdownFixtures)
import MarkdownFixtures
#endif

final class P0FixtureTests: XCTestCase {
    func testLeadingNestedQuoteUsesContainerPaddingAndClearsItOnReuse() throws {
        let fixture = try XCTUnwrap(try MarkdownFixture.load().first { $0.id == "P0-03" })
        let view = THKMDView(frame: CGRect(x: 0, y: 0, width: 340, height: 200))
        func descendants(of parent: UIView) -> [UIView] {
            parent.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        view.setMarkdown(fixture.markdown)
        view.layoutIfNeeded()
        let textView = try XCTUnwrap(descendants(of: view).compactMap { $0 as? UITextView }.first)
        XCTAssertEqual(textView.textContainerInset.top, 18)
        let style = try XCTUnwrap(textView.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.paragraphSpacingBefore, 0)
        XCTAssertTrue(textView.text.hasPrefix("只有第二级内容"))
        let manager = try XCTUnwrap(textView.layoutManager as? THKBackgroundLayoutManager)
        XCTAssertEqual(manager.leadingQuotePadding, 18)
        let bottomPadding = THKBlockQuoteMetrics.verticalPaddingBottom
            + THKBlockQuoteMetrics.secondLevelBottomSpacing
            + THKBlockQuoteMetrics.interiorLineSpacing
        XCTAssertEqual(textView.textContainerInset.bottom, bottomPadding)
        XCTAssertEqual(manager.trailingQuotePadding, bottomPadding)
        let lastStyle = try XCTUnwrap(textView.textStorage.attribute(.paragraphStyle, at: textView.textStorage.length - 1, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(lastStyle.paragraphSpacing, 0)

        view.setMarkdown("普通文本")
        XCTAssertEqual(textView.textContainerInset.top, 0)
        XCTAssertEqual(manager.leadingQuotePadding, 0)
        XCTAssertEqual(textView.textContainerInset.bottom, 0)
        XCTAssertEqual(manager.trailingQuotePadding, 0)
        XCTAssertEqual(textView.text, "普通文本")
    }

    func testNestedQuoteParagraphSpacingDoesNotAccumulate() throws {
        let fixture = try XCTUnwrap(try MarkdownFixture.load().first { $0.id == "P0-02" })
        let text = NSMutableAttributedString()
        for segment in DefaultMarkdownRenderer().render(fixture.markdown) {
            if case .text(let value, _) = segment { text.append(value) }
        }
        func style(at word: String) throws -> NSParagraphStyle {
            let range = (text.string as NSString).range(of: word)
            XCTAssertNotEqual(range.location, NSNotFound)
            guard range.location != NSNotFound else { return NSParagraphStyle.default }
            return try XCTUnwrap(text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        }
        for word in ["外层引用", "内层第一段", "内层第二段"] {
            let paragraph = try style(at: word)
            XCTAssertEqual(paragraph.lineSpacing, 2)
            XCTAssertEqual(paragraph.paragraphSpacing, word == "内层第二段" ? 12 : 2)
        }
        XCTAssertEqual(try style(at: "内层第一段").paragraphSpacingBefore, 10)
        XCTAssertEqual(try style(at: "内层第二段").paragraphSpacingBefore, 0)
        XCTAssertEqual(try style(at: "外层结尾").paragraphSpacing, THKBlockQuoteMetrics.verticalPaddingBottom)
    }

    func testQuoteSoftBreakAndExplicitHardBreak() throws {
        let renderer = DefaultMarkdownRenderer()
        func quoteText(_ source: String) throws -> String {
            let segments = renderer.render(source)
            guard case .text(_, let copies)? = segments.first else {
                XCTFail("Expected a quote text segment")
                return ""
            }
            return try XCTUnwrap(copies.first).text
        }
        XCTAssertEqual(try quoteText("> 第一行\n> 第二行"), "第一行 第二行")
        XCTAssertEqual(try quoteText("> 第一行  \n> 第二行"), "第一行\n第二行")
    }

    func testQuoteCopyButtonFollowsTextViewWidthAfterInitialLayoutAndResize() throws {
        let fixture = try XCTUnwrap(try MarkdownFixture.load().first { $0.id == "P0-01" })
        let view = THKMDView(frame: .zero)
        view.setMarkdown(fixture.markdown)
        func descendants(of parent: UIView) -> [UIView] {
            parent.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        for width in [CGFloat(340), CGFloat(260)] {
            view.frame = CGRect(x: 0, y: 0, width: width, height: 150)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            let textView = try XCTUnwrap(descendants(of: view).compactMap { $0 as? UITextView }.first)
            textView.setNeedsLayout()
            textView.layoutIfNeeded()
            let button = try XCTUnwrap(textView.subviews.compactMap { $0 as? UIButton }.first)
            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(button.frame.maxX, textView.bounds.width - 4, accuracy: 0.5)
            XCTAssertEqual(button.frame.width, 32)
        }
    }

    private func fingerprint(_ segments: [THKRenderSegment]) -> [String] {
        segments.map { segment in
            switch segment {
            case .text(let text, _): return "text:" + text.string
            case .table(let table):
                return "table:" + ([table.headerCells] + table.rows).map { $0.map(\.string).joined(separator: " | ") }.joined(separator: "\n")
            case .diagram(let source): return "diagram:" + source
            }
        }
    }

    func testSharedCatalogRendersEveryPrefixAndFinalContracts() throws {
        let fixtures = try MarkdownFixture.load()
        XCTAssertEqual(fixtures.count, 18)
        let renderer = DefaultMarkdownRenderer()
        for fixture in fixtures {
            var prefix = ""
            var segments: [THKRenderSegment] = []
            for (index, chunk) in fixture.chunks.enumerated() {
                prefix += chunk
                segments = renderer.render(prefix)
                for checkpoint in fixture.checkpoints where checkpoint.afterChunk == index + 1 {
                    let tables = segments.filter { if case .table = $0 { return true }; return false }.count
                    let diagrams = segments.filter { if case .diagram = $0 { return true }; return false }.count
                    XCTAssertEqual(tables, checkpoint.tableCount, fixture.id)
                    XCTAssertEqual(diagrams, checkpoint.diagramCount, fixture.id)
                    let plain = fingerprint(segments).joined(separator: "\n")
                    for fragment in checkpoint.textContains { XCTAssertTrue(plain.contains(fragment), fixture.id) }
                }
                for segment in segments {
                    guard case .text(let text, let copies) = segment else { continue }
                    for copy in copies {
                        XCTAssertGreaterThan(copy.range.length, 0, fixture.id)
                        XCTAssertLessThanOrEqual(NSMaxRange(copy.range), text.length, fixture.id)
                        if NSMaxRange(copy.range) <= text.length {
                            XCTAssertEqual(copy.text, (text.string as NSString).substring(with: copy.range), fixture.id)
                        }
                    }
                }
            }
            XCTAssertEqual(prefix, fixture.markdown, fixture.id)
            XCTAssertEqual(fingerprint(segments), fingerprint(renderer.render(fixture.markdown)), fixture.id)
            let plain = fingerprint(segments).joined(separator: "\n")
            for fragment in fixture.expected.textContains { XCTAssertTrue(plain.contains(fragment), "\(fixture.id): \(fragment)") }
            var tableCount = 0
            var diagramCount = 0
            var copies: [String] = []
            for segment in segments {
                switch segment {
                case .text(_, let blocks): copies += blocks.map(\.text)
                case .table: tableCount += 1
                case .diagram: diagramCount += 1
                }
            }
            XCTAssertEqual(tableCount, fixture.expected.tableCount, fixture.id)
            XCTAssertEqual(diagramCount, fixture.expected.diagramCount, fixture.id)
            for expected in fixture.expected.copyTexts { XCTAssertTrue(copies.contains(expected), "\(fixture.id): copy \(expected)") }
        }
    }

    func testNestedListKeepsDistinctIndentsAndCodeGutter() throws {
        let fixtures = try MarkdownFixture.load()
        let renderer = DefaultMarkdownRenderer()
        let fixture = try XCTUnwrap(fixtures.first { $0.id == "P0-07" })
        let text = NSMutableAttributedString()
        for segment in renderer.render(fixture.markdown) {
            if case .text(let value, _) = segment { text.append(value) }
        }
        let indents = ["一级", "二级", "三级内容"].map { word -> CGFloat in
            let index = (text.string as NSString).range(of: word).location
            return (text.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        }
        XCTAssertLessThan(indents[0], indents[1])
        XCTAssertLessThan(indents[1], indents[2])
        let codeCase = try XCTUnwrap(fixtures.first { $0.id == "P0-06" })
        for segment in renderer.render(codeCase.markdown) {
            guard case .text(let text, let copies) = segment else { continue }
            for copy in copies {
                let style = text.attribute(.paragraphStyle, at: copy.range.location, effectiveRange: nil) as? NSParagraphStyle
                XCTAssertLessThanOrEqual(try XCTUnwrap(style).tailIndent, -40)
            }
        }
    }

    func testTableLinkUsesHostCallback() throws {
        let fixture = try XCTUnwrap(try MarkdownFixture.load().first { $0.id == "P0-10" })
        let table = THKTableView()
        var tapped: URL?
        table.onLinkTap = { tapped = $0; return true }
        for segment in DefaultMarkdownRenderer().render(fixture.markdown) {
            if case .table(let model) = segment { table.configure(model: model, theme: .default) }
        }
        let url = try XCTUnwrap(URL(string: "https://example.com/p0"))
        XCTAssertFalse(table.textView(UITextView(), shouldInteractWith: url, in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction))
        XCTAssertEqual(tapped, url)
    }

    func testTableImagesUseInjectedLoader() throws {
        final class Loader: THKImageLoading {
            let onLoad: (URL) -> Void
            init(_ onLoad: @escaping (URL) -> Void) { self.onLoad = onLoad }
            func load(url: URL) async -> UIImage? { onLoad(url); return nil }
        }
        let loaded = expectation(description: "Both table images reach the host image loader")
        loaded.expectedFulfillmentCount = 2
        let view = THKMDView()
        view.imageLoader = Loader { _ in loaded.fulfill() }
        let fixture = try XCTUnwrap(try MarkdownFixture.load().first { $0.id == "P0-11" })
        view.setMarkdown(fixture.markdown)
        wait(for: [loaded], timeout: 2)
        view.reset()
    }

    #if canImport(MarkdownFixtures)
    func testStreamingSchedulerRendersEachSharedChunk() throws {
        for fixture in try MarkdownFixture.load() {
            let scheduler = FakeScheduler()
            let buffer = StreamingMarkdownBuffer(debounceInterval: 0.032, scheduler: scheduler)
            let renderer = DefaultMarkdownRenderer()
            var renders = 0
            var last: [String] = []
            buffer.onRender = { source in renders += 1; last = self.fingerprint(renderer.render(source)) }
            var prefix = ""
            for chunk in fixture.chunks {
                prefix += chunk
                buffer.append(chunk)
                scheduler.fireAll()
                XCTAssertEqual(last, fingerprint(renderer.render(prefix)), fixture.id)
            }
            XCTAssertEqual(renders, fixture.chunks.count, fixture.id)
        }
    }
    #endif
}
