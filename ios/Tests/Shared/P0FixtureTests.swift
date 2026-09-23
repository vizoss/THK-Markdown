import XCTest
import UIKit
@testable import THKMDView
#if canImport(MarkdownFixtures)
import MarkdownFixtures
#endif

final class P0FixtureTests: XCTestCase {
    func testP3SyntaxIsolationAndNumbering() {
        let source = "先[^b] 后[^a] 再[^b]。\n\n[^a]: A\n[^b]: B\n[^unused]: UNUSED"
        let prepared = THKMarkdownExtensions.prepare(source)
        XCTAssertTrue(prepared.contains("先[1](thk-footnote://reference) 后[2](thk-footnote://reference)"))
        XCTAssertTrue(prepared.contains("1. B\n2. A"))
        XCTAssertFalse(prepared.contains("UNUSED"))
        for literal in ["`$x$ [^a]`", "```text\n$x$\n[^a]: not a note\n```", "    $x$", "[url](https://example.com/$x$)", "\\$x\\$"] {
            XCTAssertEqual(THKMarkdownExtensions.prepare(literal), literal)
        }
        XCTAssertEqual(THKMarkdownExtensions.prepare("[^missing]"), "[^missing]")
        XCTAssertFalse(THKMarkdownExtensions.prepare("$$\nx+1").contains("thk-math"))
        XCTAssertTrue(THKMarkdownExtensions.prepare("$\\frac{a}{b}$").contains("thk-math://inline/"))
    }

    func testP3AlertAndFootnoteTheme() throws {
        var theme = THKMDTheme.default
        theme.alertNoteColor = .purple
        theme.footnoteScale = 0.6
        let renderer = DefaultMarkdownRenderer(theme: theme)
        guard case .text(let text, _) = renderer.render("> [!NOTE]\n> 内容").first else { return XCTFail("alert") }
        XCTAssertTrue(text.string.hasPrefix("NOTE\n"))
        XCTAssertEqual(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .purple)
        let notes = renderer.render("正文[^a]。\n\n[^a]: 定义")
        guard case .text(let note, _) = notes.first else { return XCTFail("footnote") }
        let index = (note.string as NSString).range(of: "1").location
        XCTAssertNotEqual(index, NSNotFound)
        if index != NSNotFound {
            XCTAssertNil(note.attribute(.link, at: index, effectiveRange: nil))
            let font = try XCTUnwrap(note.attribute(.font, at: index, effectiveRange: nil) as? UIFont)
            XCTAssertEqual(font.pointSize, theme.bodyFontSize * theme.footnoteScale, accuracy: 0.01)
        }
    }
    func testLargeFontSeparatorsAndNestedQuoteSpacing() throws {
        var theme = THKMDTheme.default
        theme.bodyFontSize = 24
        let renderer = DefaultMarkdownRenderer(theme: theme)
        let cases = try MarkdownFixture.loadAll().filter { ["P0-12", "P0-13", "P1-43"].contains($0.id) }
        for fixture in cases {
            for segment in renderer.render(fixture.markdown) {
                guard case .text(let text, _) = segment else { continue }
                for offset in 0..<text.length {
                    let character = (text.string as NSString).substring(with: NSRange(location: offset, length: 1))
                    if character == "\n" || character == "|" {
                        let font = try XCTUnwrap(text.attribute(.font, at: offset, effectiveRange: nil) as? UIFont)
                        XCTAssertEqual(font.pointSize, 24, fixture.id)
                    }
                }
            }
        }
        let source = "- 外层\n\n  > 第一段\n  >\n  >> 内层\n\n- 结束"
        guard case .text(let text, _) = renderer.render(source).first else { return XCTFail("text") }
        let index = (text.string as NSString).range(of: "内层").location
        let style = try XCTUnwrap(text.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertGreaterThanOrEqual(style.paragraphSpacingBefore, 10)
        XCTAssertGreaterThanOrEqual(style.paragraphSpacing, 10)
    }

    func testHeadingCodeUsesCodeSizeTimesHeadingScale() throws {
        var theme = THKMDTheme.default
        theme.bodyFontSize = 24
        theme.codeFontSize = 13
        let renderer = DefaultMarkdownRenderer(theme: theme)
        guard case .text(let text, _) = renderer.render("## 标题 `code`").first else { return XCTFail("text") }
        let index = (text.string as NSString).range(of: "code").location
        let font = try XCTUnwrap(text.attribute(.font, at: index, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(font.pointSize, theme.codeFontSize * theme.heading2Scale, accuracy: 0.01)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    }

    func testHeaderThemePreservesLinkAndCodeColors() throws {
        var theme = THKMDTheme.default
        theme.headingTextColor = .orange
        theme.bodyTextColor = .black
        theme.linkColor = .blue
        theme.codeTextColor = .purple
        let renderer = DefaultMarkdownRenderer(theme: theme)
        guard case .table(let table) = renderer.render("| 标题 [链接](https://example.com) `code` |\n| --- |\n| 正文 |").first else { return XCTFail("table") }
        let header = try XCTUnwrap(table.headerCells.first)
        for (word, color) in [("标题", theme.headingTextColor), ("链接", theme.linkColor), ("code", theme.codeTextColor)] {
            let index = (header.string as NSString).range(of: word).location
            XCTAssertEqual(header.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor, color)
        }
    }

    func testHTMLFallbackDoesNotDuplicateBlockLineEndings() {
        let renderer = DefaultMarkdownRenderer()
        let source = "<div>原始 HTML 块</div>\n\n正文含 <b>标签</b>"
        guard case .text(let text, _) = renderer.render(source).first else { return XCTFail("text") }
        XCTAssertEqual(text.string, source)
        XCTAssertEqual(thkTrimBlockLineEndings("  <div>\r\n内容\r\n</div>\r\n"), "  <div>\r\n内容\r\n</div>")
    }

    func testCodeAtContainerEdgesReservesPaddingAndClearsOnReuse() throws {
        let fixtures = try MarkdownFixture.load(suite: "p1")
            .filter { ["P1-25", "P1-26", "P1-27", "P1-28"].contains($0.id) }
        XCTAssertEqual(fixtures.count, 4)
        func descendants(_ parent: UIView) -> [UIView] {
            parent.subviews.flatMap { [$0] + descendants($0) }
        }
        let view = THKMDView(frame: CGRect(x: 0, y: 0, width: 340, height: 300))
        for fixture in fixtures {
            view.setMarkdown(fixture.markdown)
            view.layoutIfNeeded()
            let text = try XCTUnwrap(descendants(view).compactMap { $0 as? UITextView }.first)
            XCTAssertEqual(text.textContainerInset.top, THKCodeBlockMetrics.verticalPaddingTop, fixture.id)
            XCTAssertEqual(text.textContainerInset.bottom, THKCodeBlockMetrics.verticalPaddingBottom, fixture.id)
            let first = try XCTUnwrap(text.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            let last = try XCTUnwrap(text.textStorage.attribute(.paragraphStyle, at: text.textStorage.length - 1, effectiveRange: nil) as? NSParagraphStyle)
            XCTAssertEqual(first.paragraphSpacingBefore, 0)
            XCTAssertEqual(last.paragraphSpacing, 0)
            XCTAssertEqual(text.text, fixture.expected.copyTexts.first, "Padding must not add copyable whitespace")
            view.setMarkdown("普通正文")
            view.layoutIfNeeded()
            XCTAssertEqual(text.textContainerInset, .zero, "Reused body must not retain code padding")
        }
    }

    func testShortTableColumnsHaveSharedMinimumWidth() throws {
        let renderer = DefaultMarkdownRenderer()
        let model = try XCTUnwrap(renderer.render("| 甲 | 乙 |\n| --- | --- |\n| 一 | 二 |").compactMap {
            if case .table(let model) = $0 { return model }; return nil
        }.first)
        let table = THKTableView()
        table.configure(model: model, theme: .default)
        XCTAssertEqual(table.contentSize.width, 96, accuracy: 0.5,
                       "Two 48pt columns, with no additional width for borders")
    }

    func testHostLinkInterceptionMatchesBodyAndEmbeddedTable() throws {
        let view = THKMDView(frame: CGRect(x: 0, y: 0, width: 340, height: 240))
        view.setMarkdown("| 链接 |\n| --- |\n| [示例](https://example.com) |")
        func descendants(_ parent: UIView) -> [UIView] {
            parent.subviews.flatMap { [$0] + descendants($0) }
        }
        let table = try XCTUnwrap(descendants(view).compactMap { $0 as? THKTableView }.first)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        for allow in [false, true] {
            var received: [URL] = []
            view.onLinkTap = { received.append($0); return allow }
            XCTAssertEqual(view.textView(UITextView(), shouldInteractWith: url,
                in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction), allow)
            XCTAssertEqual(table.textView(UITextView(), shouldInteractWith: url,
                in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction), allow)
            XCTAssertEqual(received, [url, url])
        }
    }

    func testEmptyCodeBlocksDoNotAddParagraphSeparators() {
        let renderer = DefaultMarkdownRenderer()
        let empty = "```text\n```"
        for (source, expected) in [
            (empty + "\n\n尾部正文", "尾部正文"),
            ("前文\n\n" + empty, "前文"),
            ("前文\n\n" + empty + "\n\n尾部正文", "前文\n\n尾部正文"),
            (empty + "\n\n" + empty + "\n\n尾部正文", "尾部正文"),
            ("> ```text\n> ```\n>\n> 尾部正文", "> 尾部正文")
        ] {
            let segments = renderer.render(source)
            XCTAssertEqual(fingerprint(segments), fingerprint(renderer.render(expected)), source)
            for segment in segments {
                if case .text(_, let copies) = segment {
                    XCTAssertTrue(copies.allSatisfy { !$0.text.isEmpty }, source)
                }
            }
        }
        XCTAssertTrue(renderer.render(empty).isEmpty)
    }

    func testChineseEmphasisKeepsSkewAcrossContainers() {
        let renderer = DefaultMarkdownRenderer()
        for source in ["*中文 English* 普通", "***中文 English*** 普通",
                       "## *中文 English* 普通", "> *中文 English* 普通",
                       "[*中文 English*](https://example.com) 普通",
                       "| 内容 |\n| --- |\n| *中文 English* 普通 |"] {
            let texts = renderer.render(source).flatMap { segment -> [NSAttributedString] in
                switch segment {
                case .text(let text, _): return [text]
                case .table(let table): return table.headerCells + table.rows.flatMap { $0 }
                case .diagram: return []
                }
            }
            guard let text = texts.first(where: { $0.string.contains("中文") }) else {
                XCTFail(source); continue
            }
            let chinese = (text.string as NSString).range(of: "中文").location
            let english = (text.string as NSString).range(of: "English").location
            let ordinary = (text.string as NSString).range(of: "普通").location
            XCTAssertEqual((text.attribute(.obliqueness, at: chinese, effectiveRange: nil) as? NSNumber)?.doubleValue, 0.2, source)
            XCTAssertNil(text.attribute(.obliqueness, at: ordinary, effectiveRange: nil), source)
            XCTAssertNil(text.attribute(.obliqueness, at: english, effectiveRange: nil), source)
            let englishFont = text.attribute(.font, at: english, effectiveRange: nil) as? UIFont
            XCTAssertTrue(englishFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true, source)
            if source.hasPrefix("***") || source.hasPrefix("##") {
                let font = text.attribute(.font, at: chinese, effectiveRange: nil) as? UIFont
                XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true, source)
            }
        }
    }

    func testInPlaceFontChangeNotifiesHostAndUpdatesQuoteHeight() throws {
        let fixture = try XCTUnwrap(MarkdownFixture.load().first { $0.id == "P0-01" })
        let view = THKMDView(frame: CGRect(x: 0, y: 0, width: 280, height: 300))
        view.setMarkdown(fixture.markdown)
        view.layoutIfNeeded()
        let smallHeight = view.intrinsicContentSize.height
        var notifications = 0
        view.onContentSizeChange = { notifications += 1 }
        var theme = view.theme
        theme.bodyFontSize = 24
        view.theme = theme
        XCTAssertGreaterThan(notifications, 0, "The table host must be asked to remeasure the existing row")
        view.layoutIfNeeded()
        XCTAssertGreaterThan(view.intrinsicContentSize.height, smallHeight)

        let fresh = THKMDView(frame: view.frame)
        fresh.theme = theme
        fresh.setMarkdown(fixture.markdown)
        fresh.layoutIfNeeded()
        XCTAssertEqual(view.intrinsicContentSize.height, fresh.intrinsicContentSize.height, accuracy: 1,
                       "Changing font in place must match leaving and reopening the fixture")
    }
    func testNestedQuoteLargeFontLineMetricsAndSpacing() throws {
        let fixture = try XCTUnwrap(MarkdownFixture.load().first { $0.id == "P0-02" })
        for size in [CGFloat(15), 24] {
            var theme = THKMDTheme.default
            theme.bodyFontSize = size
            let view = THKMDView(frame: CGRect(x: 0, y: 0, width: 340, height: 600))
            view.theme = theme
            view.setMarkdown(fixture.markdown)
            view.layoutIfNeeded()
            let stack = try XCTUnwrap(view.subviews.first as? UIStackView)
            let textView = try XCTUnwrap(stack.arrangedSubviews.first as? UITextView)
            let text = textView.textStorage
            let manager = textView.layoutManager
            manager.ensureLayout(for: textView.textContainer)
            var previousBottom: CGFloat = 0
            for label in ["外层引用。", "内层第一段。", "内层第二段。", "外层结尾。"] {
                let range = (text.string as NSString).range(of: label)
                XCTAssertNotEqual(range.location, NSNotFound)
                let glyph = manager.glyphIndexForCharacter(at: range.location)
                let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let font = try XCTUnwrap(text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont)
                let baseline = line.minY + manager.location(forGlyphAt: glyph).y
                XCTAssertGreaterThanOrEqual(baseline - font.ascender, previousBottom - 1, label)
                previousBottom = baseline - font.descender
                let style = try XCTUnwrap(text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
                if label == "内层第一段。" {
                    XCTAssertEqual(style.paragraphSpacingBefore, THKBlockQuoteMetrics.secondLevelTopSpacing)
                } else if label == "内层第二段。" {
                    XCTAssertEqual(style.paragraphSpacing, THKBlockQuoteMetrics.secondLevelBottomSpacing + THKBlockQuoteMetrics.interiorLineSpacing)
                }
            }
        }
    }
    func testLargeHeadingBeforeBodyHasUnclippedBaseline() throws {
        let view = THKMDView(frame: CGRect(x: 0, y: 0, width: 340, height: 600))
        var theme = THKMDTheme.default
        theme.bodyFontSize = 24
        view.theme = theme
        view.setMarkdown(try XCTUnwrap(MarkdownFixture.load().first { $0.id == "P0-18" }).markdown)
        view.layoutIfNeeded()
        let stack = try XCTUnwrap(view.subviews.first as? UIStackView)
        let textView = try XCTUnwrap(stack.arrangedSubviews.first as? UITextView)
        let manager = textView.layoutManager
        manager.ensureLayout(for: textView.textContainer)
        let line = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let location = manager.location(forGlyphAt: 0)
        let font = try XCTUnwrap(textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertGreaterThanOrEqual(line.minY + location.y - font.ascender, -1, "heading \(line) \(location) \(font.ascender)")
    }
    func testCopyButtonsStayVisibleAfterWidthChanges() throws {
        let fixture = try XCTUnwrap(MarkdownFixture.load().first { $0.id == "P0-05" })
        let view = THKMDView(frame: CGRect(x: 0, y: 0, width: 340, height: 600))
        view.setMarkdown(fixture.markdown)
        func descendants(_ parent: UIView) -> [UIView] { parent.subviews.flatMap { [$0] + descendants($0) } }
        for width in [CGFloat(340), 720, 340, 180, 340] {
            view.frame.size.width = width
            view.setNeedsLayout()
            view.layoutIfNeeded()
            let buttons = descendants(view).compactMap { $0 as? UIButton }
            XCTAssertEqual(buttons.count, 2)
            for button in buttons {
                XCTAssertFalse(button.isHidden)
                let rect = button.convert(button.bounds, to: view)
                XCTAssertGreaterThanOrEqual(rect.minX, 0)
                XCTAssertLessThanOrEqual(rect.maxX, width, "\(rect) at width \(width)")
            }
        }
    }
    func testP0LayoutMatrixAndRebinding() throws {
        let fixtures = try MarkdownFixture.load()
        let view = THKMDView(frame: .zero)
        for width in [CGFloat(180), 340, 720] {
            for fontSize in [CGFloat(15), 24] {
                var theme = THKMDTheme.default
                theme.bodyFontSize = fontSize
                theme.codeFontSize = fontSize
                theme.bodyTextColor = .brown
                view.theme = theme
                for fixture in fixtures {
                    view.reset()
                    view.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
                    view.setMarkdown(fixture.markdown)
                    view.layoutIfNeeded()
                    XCTAssertTrue(view.intrinsicContentSize.height.isFinite, fixture.id)
                    XCTAssertGreaterThanOrEqual(view.intrinsicContentSize.height, 0, fixture.id)
                    // A recycled view must discard pending chunks when rebound.
                    view.appendMarkdownChunk("旧片段")
                    view.reset()
                    view.setMarkdown("新消息")
                    view.layoutIfNeeded()
                }
            }
        }
    }

    func testCopyButtonsPreserveFixturePayloadExactly() throws {
        func descendants(_ parent: UIView) -> [UIView] { parent.subviews.flatMap { [$0] + descendants($0) } }
        for fixture in try MarkdownFixture.load() where !fixture.expected.copyTexts.isEmpty {
            let view = THKMDView(frame: CGRect(x: 0, y: 0, width: 340, height: 2000))
            view.setMarkdown(fixture.markdown)
            view.layoutIfNeeded()
            var values: [String] = []
            for button in descendants(view).compactMap({ $0 as? UIButton }) {
                button.sendActions(for: .touchUpInside)
                values.append(UIPasteboard.general.string ?? "")
            }
            for expected in fixture.expected.copyTexts { XCTAssertTrue(values.contains(expected), fixture.id) }
        }
    }
    func testListContainerPreservesNestedQuoteSpacing() throws {
        let fixture = try XCTUnwrap(try MarkdownFixture.load().first { $0.id == "P0-09" })
        guard case .text(let text, _) = DefaultMarkdownRenderer().render(fixture.markdown).first else {
            return XCTFail("Expected text")
        }
        let offset = (text.string as NSString).range(of: "内层引用").location
        let style = try XCTUnwrap(text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.paragraphSpacingBefore, THKBlockQuoteMetrics.secondLevelTopSpacing)
        XCTAssertGreaterThanOrEqual(style.paragraphSpacing, THKBlockQuoteMetrics.secondLevelBottomSpacing)
    }
    func testStandaloneCodeCopyButtonCentersOnFirstTextRow() throws {
        func descendants(_ parent: UIView) -> [UIView] {
            parent.subviews.flatMap { [$0] + descendants($0) }
        }
        for code in ["let answer = 42", "let answer = 42\nprint(answer)"] {
            for width: CGFloat in [180, 340] {
                for fontSize: CGFloat in [13, 24] {
                    let view = THKMDView(frame: CGRect(x: 0, y: 0, width: width, height: 240))
                    var theme = THKMDTheme.default
                    theme.codeFontSize = fontSize
                    view.theme = theme
                    view.setMarkdown("```swift\n" + code + "\n```")
                    view.layoutIfNeeded()
                    let textView = try XCTUnwrap(descendants(view).compactMap { $0 as? UITextView }.first)
                    let button = try XCTUnwrap(descendants(view).compactMap { $0 as? UIButton }.first)
                    let manager = textView.layoutManager
                    let glyph = manager.glyphIndexForCharacter(at: 0)
                    let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                    let font = try XCTUnwrap(textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
                    let baseline = textView.textContainerInset.top + line.minY + manager.location(forGlyphAt: glyph).y
                    XCTAssertEqual(button.frame.midY, baseline - (font.ascender + font.descender) / 2, accuracy: 0.5)
                    XCTAssertGreaterThanOrEqual(button.frame.minY, 0)
                    XCTAssertLessThanOrEqual(button.frame.maxY, textView.bounds.height + 0.5)
                }
            }
        }
    }

    func testQuotedCodeCopyButtonsShareTrailingColumn() throws {
        let view = THKMDView(frame: CGRect(x: 0, y: 0, width: 360, height: 240))
        view.setMarkdown("> 引用说明。\n>\n> ```swift\n> let value = 42\n> ```\n> 引用结束。")
        view.layoutIfNeeded()
        func descendants(_ parent: UIView) -> [UIView] {
            parent.subviews.flatMap { [$0] + descendants($0) }
        }
        let buttons = descendants(view).compactMap { $0 as? UIButton }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(buttons.count, 2)
        guard buttons.count == 2 else { return }
        XCTAssertEqual(buttons[0].frame.minX, buttons[1].frame.minX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(buttons[1].frame.minY, buttons[0].frame.maxY)
        let textView = try XCTUnwrap(descendants(view).compactMap { $0 as? UITextView }.first)
        let style = try XCTUnwrap(textView.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.minimumLineHeight, 0, "Copy buttons must not inflate the quote header")
    }

    func testThemeControlsHeadingScaleAndMermaidFont() throws {
        var theme = THKMDTheme.default
        theme.bodyFontSize = 20
        theme.heading1Scale = 2
        let renderer = DefaultMarkdownRenderer(theme: theme)
        guard case .text(let text, _) = renderer.render("# Title").first else {
            return XCTFail("Expected heading text")
        }
        XCTAssertEqual((text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize, 40)
        let variables = try XCTUnwrap(theme.mermaidConfiguration["themeVariables"] as? [String: String])
        XCTAssertEqual(variables["fontSize"], "20.0px")
    }

    func testMermaidTemplateDoesNotCloseScriptInsideAComment() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let template = try String(contentsOf: root.appendingPathComponent("Sources/THKMDView/mermaid_template.html"), encoding: .utf8)
        // One external script and one inline script: HTML parses closing tags even
        // inside JavaScript comments, so any third occurrence terminates the code.
        XCTAssertEqual(template.lowercased().components(separatedBy: "</script>").count - 1, 2)
    }

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
        try assertCatalog(suite: "p0", count: 18)
    }

    func testP1CatalogRendersEveryPrefixAndFinalContracts() throws {
        try assertCatalog(suite: "p1", count: 60)
    }

    func testP2CatalogRendersEveryPrefixAndFinalContracts() throws {
        try assertCatalog(suite: "p2", count: 25)
    }

    func testP3CatalogRendersEveryPrefixAndFinalContracts() throws {
        try assertCatalog(suite: "p3", count: 36)
    }

    func testCombinedCatalogSuiteBoundaries() throws {
        let ids = try MarkdownFixture.loadAll().map(\.id)
        XCTAssertEqual(ids.count, 139)
        XCTAssertEqual(Array(ids[17...18]), ["P0-18", "P1-01"])
        XCTAssertEqual(Array(ids[77...78]), ["P1-60", "P2-01"])
        XCTAssertEqual(Array(ids[102...103]), ["P2-25", "P3-01"])
        XCTAssertEqual(ids.last, "P3-36")
    }

    private func assertCatalog(suite: String, count: Int) throws {
        let fixtures = try MarkdownFixture.load(suite: suite)
        XCTAssertEqual(fixtures.count, count)
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
                            XCTAssertEqual(copy.text, thkCopyText(text, range: copy.range), fixture.id)
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
            if let expected = fixture.expected.mathCount {
                var mathCount = 0
                func count(_ text: NSAttributedString) {
                    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                        if (value as? THKAsyncImageTextAttachment)?.url.scheme == "thk-math" { mathCount += 1 }
                    }
                }
                for segment in segments {
                    switch segment {
                    case .text(let text, _): count(text)
                    case .table(let table): ([table.headerCells] + table.rows).flatMap { $0 }.forEach(count)
                    case .diagram: break
                    }
                }
                XCTAssertEqual(mathCount, expected, fixture.id)
            }
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
        XCTAssertFalse(text.string.contains("\n\n"), "Nested list boundaries must not insert empty paragraphs")
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
