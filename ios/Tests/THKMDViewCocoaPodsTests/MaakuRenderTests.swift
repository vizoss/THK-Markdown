import XCTest
import Maaku
@testable import THKMDView

/// Mirrors Tests/THKMDViewTests/RenderTests.swift category-for-category, but exercises
/// the Maaku-backed `DefaultMarkdownRenderer` (Sources/THKMDView/CocoaPods/
/// MaakuMarkdownRenderer.swift) that ships in the CocoaPods distribution instead of the
/// swift-markdown-backed one SPM consumers get. Both are meant to be behaviorally
/// equivalent, so these assertions intentionally track the SPM suite's.
final class MaakuRenderTests: XCTestCase {
    private var renderer: DefaultMarkdownRenderer!

    override func setUp() {
        super.setUp()
        renderer = DefaultMarkdownRenderer()
    }

    private func fontAttribute(in attributed: NSAttributedString, at index: Int) -> UIFont? {
        attributed.attribute(.font, at: index, effectiveRange: nil) as? UIFont
    }

    private func singleText(_ markdown: String, file: StaticString = #filePath, line: UInt = #line) -> NSAttributedString {
        let segments = renderer.render(markdown)
        guard segments.count == 1, case .text(let attributed, _) = segments[0] else {
            XCTFail("expected exactly one text segment for \(markdown.debugDescription), got \(segments.count) segment(s)", file: file, line: line)
            return NSAttributedString()
        }
        return attributed
    }

    func testPlainTextRoundTrips() {
        let attributed = singleText("Hello, world!")
        XCTAssertEqual(attributed.string, "Hello, world!")
    }

    func testBoldAppliesBoldFontTrait() {
        let attributed = singleText("This is **bold** text.")
        XCTAssertEqual(attributed.string, "This is bold text.")
        let range = (attributed.string as NSString).range(of: "bold")
        let font = fontAttribute(in: attributed, at: range.location)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testItalicAppliesItalicFontTrait() {
        let attributed = singleText("This is _italic_ text.")
        XCTAssertEqual(attributed.string, "This is italic text.")
        let range = (attributed.string as NSString).range(of: "italic")
        let font = fontAttribute(in: attributed, at: range.location)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    func testBoldItalicCombineTraits() {
        let attributed = singleText("This is ***both*** text.")
        let range = (attributed.string as NSString).range(of: "both")
        let font = fontAttribute(in: attributed, at: range.location)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    func testInlineCodeUsesMonospaceFontAndBackgroundAttribute() {
        let attributed = singleText("Run `let x = 1` now.")
        XCTAssertEqual(attributed.string, "Run let x = 1 now.")
        let range = (attributed.string as NSString).range(of: "let x = 1")
        let font = fontAttribute(in: attributed, at: range.location)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        let background = attributed.attribute(.thkInlineCodeBackground, at: range.location, effectiveRange: nil)
        XCTAssertNotNil(background)

        // Text outside the inline code range must not carry the background attribute.
        let outsideBackground = attributed.attribute(.thkInlineCodeBackground, at: 0, effectiveRange: nil)
        XCTAssertNil(outsideBackground)
    }

    func testHeadingIsBoldAndLargerThanBody() {
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let renderer = DefaultMarkdownRenderer(baseFont: bodyFont)
        let segments = renderer.render("# Big Heading")
        guard case .text(let attributed, _) = segments[0] else { return XCTFail("expected a text segment") }
        XCTAssertEqual(attributed.string, "Big Heading")
        let font = fontAttribute(in: attributed, at: 0)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertGreaterThan(font!.pointSize, bodyFont.pointSize)
    }

    func testAllSixHeadingLevelsAreDistinctAndBold() {
        func headingFont(_ level: Int) -> UIFont {
            let marker = String(repeating: "#", count: level)
            return fontAttribute(in: singleText("\(marker) Heading"), at: 0)!
        }
        let sizes = (1...6).map { headingFont($0).pointSize }
        for level in 1...6 {
            XCTAssertTrue(headingFont(level).fontDescriptor.symbolicTraits.contains(.traitBold), "h\(level) should be bold")
        }
        for i in 0..<(sizes.count - 1) {
            XCTAssertGreaterThanOrEqual(sizes[i], sizes[i + 1], "h\(i + 1) should be at least as large as h\(i + 2)")
        }
        XCTAssertGreaterThan(sizes.first!, sizes.last!, "h1 should be strictly larger than h6")
    }

    func testLinkHasURLAttribute() {
        let attributed = singleText("See [Apple](https://apple.com) for more.")
        let range = (attributed.string as NSString).range(of: "Apple")
        let url = attributed.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        XCTAssertEqual(url, URL(string: "https://apple.com"))
    }

    func testAutolinkHasURLAttribute() {
        let attributed = singleText("Go to <https://example.com> now.")
        let range = (attributed.string as NSString).range(of: "https://example.com")
        let url = attributed.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        XCTAssertEqual(url, URL(string: "https://example.com"))
    }

    func testReferenceStyleLinkHasURLAttribute() {
        let attributed = singleText("[Apple][ref]\n\n[ref]: https://apple.com")
        let range = (attributed.string as NSString).range(of: "Apple")
        let url = attributed.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        XCTAssertEqual(url, URL(string: "https://apple.com"))
    }

    func testBlockQuoteCarriesCustomBarAttribute() {
        let attributed = singleText("> A wise quote.")
        XCTAssertEqual(attributed.string, "A wise quote.")
        let depth = attributed.attribute(.thkBlockQuoteBar, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(depth, 1)
        let paragraphStyle = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(paragraphStyle)
        XCTAssertGreaterThan(paragraphStyle!.headIndent, 0)
    }

    func testNestedBlockQuoteIncreasesDepth() {
        let attributed = singleText("> Outer\n> > Inner")
        let range = (attributed.string as NSString).range(of: "Inner")
        let depth = attributed.attribute(.thkBlockQuoteBar, at: range.location, effectiveRange: nil) as? Int
        XCTAssertEqual(depth, 2)
    }

    func testBlockQuoteCarriesBackgroundAttribute() {
        let attributed = singleText("> A wise quote.")
        XCTAssertNotNil(attributed.attribute(.thkBlockQuoteBackground, at: 0, effectiveRange: nil))
    }

    // Guards the nested-quote fix: only the OUTERMOST level is tagged, and it's tagged as one
    // continuous run spanning both the outer text and the nested quote's own text, so
    // THKBackgroundLayoutManager paints one seamless rounded background instead of a separate,
    // independently-rounded fill starting where the nested quote begins.
    func testNestedBlockQuoteBackgroundIsOneContinuousOutermostRangeOnly() {
        let attributed = singleText("> Outer\n> > Inner")
        let outerRange = (attributed.string as NSString).range(of: "Outer")
        let innerRange = (attributed.string as NSString).range(of: "Inner")

        let fullRange = NSRange(location: 0, length: attributed.length)
        var backgroundRange = NSRange(location: 0, length: 0)
        let value = attributed.attribute(.thkBlockQuoteBackground, at: outerRange.location, longestEffectiveRange: &backgroundRange, in: fullRange)
        XCTAssertNotNil(value)
        XCTAssertTrue(
            NSLocationInRange(innerRange.location, backgroundRange),
            "expected one continuous background range spanning both the outer and nested quote text"
        )
    }

    func testCodeBlockUsesMonospaceFontAndBackgroundAttribute() {
        let attributed = singleText("```\nlet x = 1\nlet y = 2\n```")
        XCTAssertTrue(attributed.string.contains("let x = 1"))
        XCTAssertTrue(attributed.string.contains("let y = 2"))
        let font = fontAttribute(in: attributed, at: 0)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        let background = attributed.attribute(.thkCodeBlockBackground, at: 0, effectiveRange: nil)
        XCTAssertNotNil(background)
        let paragraphStyle = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(paragraphStyle)
        XCTAssertGreaterThan(paragraphStyle!.headIndent, 0, "code blocks should have left padding")
    }

    func testFencedCodeBlockWithLanguageTagRendersJustTheCode() {
        let attributed = singleText("```swift\nlet x = 1\n```")
        XCTAssertEqual(attributed.string, "let x = 1")
    }

    func testIndentedCodeBlockUsesMonospaceFontAndBackgroundAttribute() {
        let attributed = singleText("    let x = 1")
        XCTAssertEqual(attributed.string, "let x = 1")
        let font = fontAttribute(in: attributed, at: 0)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        XCTAssertNotNil(attributed.attribute(.thkCodeBlockBackground, at: 0, effectiveRange: nil))
    }

    func testStrikethroughAppliesAttribute() {
        let attributed = singleText("This is ~~wrong~~ right.")
        XCTAssertEqual(attributed.string, "This is wrong right.")
        let range = (attributed.string as NSString).range(of: "wrong")
        let style = attributed.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testUnorderedListRendersBulletMarkers() {
        let attributed = singleText("- First\n- Second\n- Third")
        XCTAssertTrue(attributed.string.contains("\u{2022} First"))
        XCTAssertTrue(attributed.string.contains("\u{2022} Second"))
        XCTAssertTrue(attributed.string.contains("\u{2022} Third"))
    }

    func testOrderedListRendersNumberMarkers() {
        let attributed = singleText("1. First\n2. Second\n3. Third")
        XCTAssertTrue(attributed.string.contains("1. First"))
        XCTAssertTrue(attributed.string.contains("2. Second"))
        XCTAssertTrue(attributed.string.contains("3. Third"))
    }

    // Unlike the SPM/swift-markdown backend, Maaku's `OrderedList` (Sources/Maaku/Core/
    // OrderedList.swift) does not retain the GFM start index at all — its DocumentConverter
    // receives it (`didStartOrderedListWithStartingNumber:`) but never stores it on the
    // `OrderedList` value, so every ordered list numbers from 1 regardless of source
    // Markdown. This is a real upstream Maaku limitation (see ios/README.md), not a THKMDView
    // rendering bug, so this test documents the actual (renumbered) behavior instead of the
    // SPM suite's `testOrderedListRespectsNonOneStartIndex`.
    func testOrderedListStartIndexIsNotPreservedByMaaku() {
        let attributed = singleText("5. Five\n6. Six")
        XCTAssertTrue(attributed.string.contains("1. Five"))
        XCTAssertTrue(attributed.string.contains("2. Six"))
    }

    func testNestedListsIndentFurther() {
        let attributed = singleText("- Item 1\n  - Nested Item\n- Item 2")
        XCTAssertTrue(attributed.string.contains("\u{2022} Item 1"))
        XCTAssertTrue(attributed.string.contains("\u{2022} Nested Item"))
        XCTAssertTrue(attributed.string.contains("\u{2022} Item 2"))
    }

    func testTaskListRendersCheckboxGlyphs() {
        let attributed = singleText("- [x] Done\n- [ ] Not done")
        XCTAssertTrue(attributed.string.contains("\u{2611} Done"))
        XCTAssertTrue(attributed.string.contains("\u{2610} Not done"))
    }

    func testEscapedCharactersRenderLiterally() {
        let attributed = singleText("\\*not emphasis\\*")
        XCTAssertTrue(attributed.string.contains("*not emphasis*"))
        let range = (attributed.string as NSString).range(of: "not emphasis")
        let font = fontAttribute(in: attributed, at: range.location)
        XCTAssertFalse(font!.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    // A thematic break is drawn as a real filled rect by THKBackgroundLayoutManager (see
    // .thkThematicBreak), not a run of glyph characters — this asserts the placeholder
    // character carries that custom attribute rather than checking for any particular glyph.
    func testThematicBreakRenders() {
        let attributed = singleText("above\n\n---\n\nbelow")
        var found = false
        attributed.enumerateAttribute(.thkThematicBreak, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if value != nil { found = true }
        }
        XCTAssertTrue(found)
    }

    func testRawHTMLBlockRendersAsInertLiteralText() {
        let attributed = singleText("<script>alert(1)</script>")
        XCTAssertTrue(attributed.string.contains("<script>"))
        XCTAssertTrue(attributed.string.contains("alert(1)"))
        XCTAssertTrue(attributed.string.contains("</script>"))
    }

    func testRawInlineHTMLRendersAsInertLiteralText() {
        let attributed = singleText("before <span class=\"x\">middle</span> after")
        XCTAssertTrue(attributed.string.contains("<span class=\"x\">"))
    }

    func testImageBecomesAsyncAttachmentWithAltTextAccessibilityLabel() {
        let segments = renderer.render("![a THKMDView logo](https://example.com/logo.png)")
        guard case .text(let attributed, _) = segments[0] else { return XCTFail("expected a text segment") }
        var foundAttachment: THKAsyncImageTextAttachment?
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            foundAttachment = value as? THKAsyncImageTextAttachment
        }
        XCTAssertNotNil(foundAttachment)
        XCTAssertEqual(foundAttachment?.url, URL(string: "https://example.com/logo.png"))
        XCTAssertEqual(foundAttachment?.accessibilityLabel, "a THKMDView logo")
    }

    func testTableProducesADedicatedSegmentWithColumnAlignment() {
        let markdown = """
        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | c |
        """
        let segments = renderer.render(markdown)
        XCTAssertEqual(segments.count, 1)
        guard case .table(let model) = segments[0] else { return XCTFail("expected a table segment") }
        XCTAssertEqual(model.alignments, [.leading, .center, .trailing])
        XCTAssertEqual(model.headerCells.map(\.string), ["Left", "Center", "Right"])
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.rows[0].map(\.string), ["a", "b", "c"])
    }

    func testTableCellsRenderInlineMarkdown() {
        let markdown = """
        | Name |
        | --- |
        | **Ada** |
        """
        let segments = renderer.render(markdown)
        guard case .table(let model) = segments[0] else { return XCTFail("expected a table segment") }
        let cell = model.rows[0][0]
        let font = fontAttribute(in: cell, at: 0)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testTextAroundTableProducesSeparateSegments() {
        let markdown = """
        Intro paragraph.

        | A | B |
        | --- | --- |
        | 1 | 2 |

        Outro paragraph.
        """
        let segments = renderer.render(markdown)
        XCTAssertEqual(segments.count, 3)
        guard case .text(let intro, _) = segments[0], case .table = segments[1], case .text(let outro, _) = segments[2] else {
            return XCTFail("expected text/table/text segments, got \(segments.count)")
        }
        XCTAssertEqual(intro.string, "Intro paragraph.")
        XCTAssertEqual(outro.string, "Outro paragraph.")
    }

    func testUnterminatedCodeFenceDoesNotCrashAndRendersAsCode() {
        let attributed = singleText("```swift\nlet x = ")
        XCTAssertTrue(attributed.string.contains("let x ="))
    }

    func testUnterminatedBoldIsTreatedAsLiteralText() {
        let attributed = singleText("This is **almost bold")
        XCTAssertTrue(attributed.string.contains("**almost bold") || attributed.string.contains("almost bold"))
    }

    func testThemeColorsAreAppliedToBodyHeadingAndCode() {
        let theme = THKMDTheme(
            bodyTextColor: .systemRed,
            headingTextColor: .systemBlue,
            linkColor: .systemGreen,
            codeTextColor: .systemPurple,
            codeBackgroundColor: .black,
            codeBlockCornerRadius: 4,
            blockQuoteBarColor: .systemOrange,
            blockQuoteTextColor: .systemYellow,
            blockQuoteBackgroundColor: .systemPink,
            tableBorderColor: .brown,
            tableHeaderBackgroundColor: .cyan,
            bodyFontSize: 20,
            codeFontSize: 18
        )
        let renderer = DefaultMarkdownRenderer(theme: theme)

        guard case .text(let body, _) = renderer.render("plain text")[0] else { return XCTFail() }
        XCTAssertEqual(body.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .systemRed)
        XCTAssertEqual(fontAttribute(in: body, at: 0)?.pointSize, 20)

        guard case .text(let heading, _) = renderer.render("# Heading")[0] else { return XCTFail() }
        XCTAssertEqual(heading.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .systemBlue)

        guard case .text(let code, _) = renderer.render("`x`")[0] else { return XCTFail() }
        let range = (code.string as NSString).range(of: "x")
        XCTAssertEqual(code.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor, .systemPurple)
        XCTAssertEqual(fontAttribute(in: code, at: range.location)?.pointSize, 18)
    }

    func testCodeBlockProducesACopyableBlockWithItsCode() {
        let segments = renderer.render("```\nlet x = 1\n```")
        guard case .text(let attributed, let copyableBlocks) = segments[0] else { return XCTFail("expected a text segment") }
        XCTAssertEqual(copyableBlocks.count, 1)
        XCTAssertEqual(copyableBlocks[0].text, "let x = 1")
        XCTAssertEqual((attributed.string as NSString).substring(with: copyableBlocks[0].range), "let x = 1")
    }

    func testOutermostBlockQuoteProducesACopyableBlockWithItsText() {
        let segments = renderer.render("> A wise quote.")
        guard case .text(_, let copyableBlocks) = segments[0] else { return XCTFail("expected a text segment") }
        XCTAssertEqual(copyableBlocks.count, 1)
        XCTAssertEqual(copyableBlocks[0].text, "A wise quote.")
    }

    // Only the outermost level of a nested `> > quote` gets a copy button — same rule as the
    // rounded background fill (`testNestedBlockQuoteBackgroundIsOneContinuousOutermostRangeOnly`).
    // A single copyable block should cover the whole outer+nested text, not two separate ones.
    func testNestedBlockQuoteOnlyProducesOneCopyableBlockForTheOutermostLevel() {
        let segments = renderer.render("> Outer\n> > Inner")
        guard case .text(let attributed, let copyableBlocks) = segments[0] else { return XCTFail("expected a text segment") }
        XCTAssertEqual(copyableBlocks.count, 1)
        XCTAssertEqual(copyableBlocks[0].text, attributed.string)
        XCTAssertTrue(copyableBlocks[0].text.contains("Outer"))
        XCTAssertTrue(copyableBlocks[0].text.contains("Inner"))
    }

    func testMermaidFencedCodeBlockProducesADiagramSegmentNotACodeBlock() {
        let markdown = """
        Before.

        ```mermaid
        flowchart LR
            A --> B
        ```

        After.
        """
        let segments = renderer.render(markdown)
        XCTAssertEqual(segments.count, 3)
        guard case .text(let before, _) = segments[0] else { return XCTFail("expected a text segment") }
        guard case .diagram(let source) = segments[1] else { return XCTFail("expected a diagram segment") }
        guard case .text(let after, _) = segments[2] else { return XCTFail("expected a text segment") }
        XCTAssertEqual(before.string, "Before.")
        XCTAssertEqual(after.string, "After.")
        XCTAssertEqual(source, "flowchart LR\n    A --> B")
    }

    func testMermaidLanguageTagIsCaseInsensitive() {
        let segments = renderer.render("```MermaiD\nflowchart LR\n  A --> B\n```")
        XCTAssertEqual(segments.count, 1)
        guard case .diagram = segments[0] else { return XCTFail("expected a diagram segment") }
    }

    // Guards the CocoaPods half of the dual resource-bundling setup — this is the one path
    // that actually exercises `s.resource_bundles` in THKMDView.podspec (a `pod lib lint` run
    // compiles this test target against the real generated `THKMDView.bundle`, whether that
    // lands inside a static-library main app bundle or a dynamic THKMDView.framework, per
    // THKMermaidView.resourceURL(name:ext:)'s `Bundle(for:)` lookup). A missing/misconfigured
    // resource bundle otherwise compiles fine but fails silently at runtime, so this actually
    // loads and inspects the bundled files' content rather than only checking the URLs are
    // non-nil.
    func testMermaidResourcesAreBundledAndLoadableAtRuntime() {
        guard let templateURL = THKMermaidView.resourceURL(name: "mermaid_template", ext: "html") else {
            return XCTFail("mermaid_template.html was not found in the CocoaPods THKMDView.bundle")
        }
        let scriptURL = templateURL.deletingLastPathComponent().appendingPathComponent("mermaid.min.js")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return XCTFail("mermaid.min.js was not found next to mermaid_template.html in the CocoaPods THKMDView.bundle")
        }
        guard let templateHTML = try? String(contentsOf: templateURL, encoding: .utf8) else {
            return XCTFail("mermaid_template.html could not be read")
        }
        XCTAssertTrue(templateHTML.contains("mermaid.min.js"))
        XCTAssertTrue(templateHTML.contains("THK_MERMAID_SOURCE_B64"))
        guard let scriptData = try? Data(contentsOf: scriptURL) else {
            return XCTFail("mermaid.min.js could not be read")
        }
        XCTAssertGreaterThan(scriptData.count, 100_000, "expected a real vendored mermaid.js, not a stub")
    }
}
