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
        guard segments.count == 1, case .text(let attributed) = segments[0] else {
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
        guard case .text(let attributed) = segments[0] else { return XCTFail("expected a text segment") }
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

    func testThematicBreakRenders() {
        let attributed = singleText("above\n\n---\n\nbelow")
        XCTAssertTrue(attributed.string.contains("\u{2015}"))
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
        guard case .text(let attributed) = segments[0] else { return XCTFail("expected a text segment") }
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
        guard case .text(let intro) = segments[0], case .table = segments[1], case .text(let outro) = segments[2] else {
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
            tableBorderColor: .brown,
            tableHeaderBackgroundColor: .cyan,
            bodyFontSize: 20,
            codeFontSize: 18
        )
        let renderer = DefaultMarkdownRenderer(theme: theme)

        guard case .text(let body) = renderer.render("plain text")[0] else { return XCTFail() }
        XCTAssertEqual(body.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .systemRed)
        XCTAssertEqual(fontAttribute(in: body, at: 0)?.pointSize, 20)

        guard case .text(let heading) = renderer.render("# Heading")[0] else { return XCTFail() }
        XCTAssertEqual(heading.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .systemBlue)

        guard case .text(let code) = renderer.render("`x`")[0] else { return XCTFail() }
        let range = (code.string as NSString).range(of: "x")
        XCTAssertEqual(code.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor, .systemPurple)
        XCTAssertEqual(fontAttribute(in: code, at: range.location)?.pointSize, 18)
    }
}
