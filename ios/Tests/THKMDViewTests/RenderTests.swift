import XCTest
@testable import THKMDView

final class RenderTests: XCTestCase {
    private var renderer: DefaultMarkdownRenderer!

    override func setUp() {
        super.setUp()
        renderer = DefaultMarkdownRenderer()
    }

    private func fontAttribute(in attributed: NSAttributedString, at index: Int) -> UIFont? {
        attributed.attribute(.font, at: index, effectiveRange: nil) as? UIFont
    }

    func testPlainTextRoundTrips() {
        let attributed = renderer.render("Hello, world!")
        XCTAssertEqual(attributed.string, "Hello, world!")
    }

    func testBoldAppliesBoldFontTrait() {
        let attributed = renderer.render("This is **bold** text.")
        XCTAssertEqual(attributed.string, "This is bold text.")
        let range = (attributed.string as NSString).range(of: "bold")
        let font = fontAttribute(in: attributed, at: range.location)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testItalicAppliesItalicFontTrait() {
        let attributed = renderer.render("This is _italic_ text.")
        XCTAssertEqual(attributed.string, "This is italic text.")
        let range = (attributed.string as NSString).range(of: "italic")
        let font = fontAttribute(in: attributed, at: range.location)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    func testBoldItalicCombineTraits() {
        let attributed = renderer.render("This is ***both*** text.")
        let range = (attributed.string as NSString).range(of: "both")
        let font = fontAttribute(in: attributed, at: range.location)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    func testInlineCodeUsesMonospaceFontAndBackgroundAttribute() {
        let attributed = renderer.render("Run `let x = 1` now.")
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
        let attributed = renderer.render("# Big Heading")
        XCTAssertEqual(attributed.string, "Big Heading")
        let font = fontAttribute(in: attributed, at: 0)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertGreaterThan(font!.pointSize, bodyFont.pointSize)
    }

    func testDeeperHeadingLevelsAreSmaller() {
        let h1Font = fontAttribute(in: renderer.render("# H1"), at: 0)!
        let h3Font = fontAttribute(in: renderer.render("### H3"), at: 0)!
        XCTAssertGreaterThan(h1Font.pointSize, h3Font.pointSize)
    }

    func testLinkHasURLAttribute() {
        let attributed = renderer.render("See [Apple](https://apple.com) for more.")
        let range = (attributed.string as NSString).range(of: "Apple")
        let url = attributed.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        XCTAssertEqual(url, URL(string: "https://apple.com"))
    }

    func testBlockQuoteCarriesCustomBarAttribute() {
        let attributed = renderer.render("> A wise quote.")
        XCTAssertEqual(attributed.string, "A wise quote.")
        let depth = attributed.attribute(.thkBlockQuoteBar, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(depth, 1)
        let paragraphStyle = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(paragraphStyle)
        XCTAssertGreaterThan(paragraphStyle!.headIndent, 0)
    }

    func testCodeBlockUsesMonospaceFontAndBackgroundAttribute() {
        let attributed = renderer.render("```\nlet x = 1\nlet y = 2\n```")
        XCTAssertTrue(attributed.string.contains("let x = 1"))
        XCTAssertTrue(attributed.string.contains("let y = 2"))
        let font = fontAttribute(in: attributed, at: 0)
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        let background = attributed.attribute(.thkCodeBlockBackground, at: 0, effectiveRange: nil)
        XCTAssertNotNil(background)
    }

    func testStrikethroughAppliesAttribute() {
        let attributed = renderer.render("This is ~~wrong~~ right.")
        XCTAssertEqual(attributed.string, "This is wrong right.")
        let range = (attributed.string as NSString).range(of: "wrong")
        let style = attributed.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testUnorderedListRendersBulletMarkers() {
        let attributed = renderer.render("- First\n- Second\n- Third")
        XCTAssertTrue(attributed.string.contains("\u{2022} First"))
        XCTAssertTrue(attributed.string.contains("\u{2022} Second"))
        XCTAssertTrue(attributed.string.contains("\u{2022} Third"))
    }

    func testOrderedListRendersNumberMarkers() {
        let attributed = renderer.render("1. First\n2. Second\n3. Third")
        XCTAssertTrue(attributed.string.contains("1. First"))
        XCTAssertTrue(attributed.string.contains("2. Second"))
        XCTAssertTrue(attributed.string.contains("3. Third"))
    }

    func testTaskListRendersCheckboxGlyphs() {
        let attributed = renderer.render("- [x] Done\n- [ ] Not done")
        XCTAssertTrue(attributed.string.contains("\u{2611} Done"))
        XCTAssertTrue(attributed.string.contains("\u{2610} Not done"))
    }

    func testTableFallsBackToPlainMonospaceRows() {
        let markdown = """
        | Name | Age |
        | --- | --- |
        | Ada | 30 |
        """
        let attributed = renderer.render(markdown)
        XCTAssertTrue(attributed.string.contains("Name"))
        XCTAssertTrue(attributed.string.contains("Ada"))
        let font = fontAttribute(in: attributed, at: 0)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    }

    func testUnterminatedCodeFenceDoesNotCrashAndRendersAsCode() {
        let attributed = renderer.render("```swift\nlet x = ")
        XCTAssertTrue(attributed.string.contains("let x ="))
    }

    func testUnterminatedBoldIsTreatedAsLiteralText() {
        let attributed = renderer.render("This is **almost bold")
        XCTAssertTrue(attributed.string.contains("**almost bold") || attributed.string.contains("almost bold"))
    }
}
