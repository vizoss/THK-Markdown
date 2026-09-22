import UIKit
import Markdown

public protocol MarkdownRendering {
    func render(_ markdown: String) -> NSAttributedString
}

public extension NSAttributedString.Key {
    /// Paints a rounded background behind inline `code` spans. No built-in
    /// NSAttributedString attribute does this, so THKBackgroundLayoutManager reads it.
    static let thkInlineCodeBackground = NSAttributedString.Key("THKInlineCodeBackground")
    /// Paints a full-width background behind fenced/indented code blocks.
    static let thkCodeBlockBackground = NSAttributedString.Key("THKCodeBlockBackground")
    /// Paints a left-edge vertical bar behind block quote ranges. Value is the nesting depth (Int).
    static let thkBlockQuoteBar = NSAttributedString.Key("THKBlockQuoteBar")
}

public final class DefaultMarkdownRenderer: MarkdownRendering {
    public var baseFont: UIFont

    public init(baseFont: UIFont = UIFont.preferredFont(forTextStyle: .body)) {
        self.baseFont = baseFont
    }

    public func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        var visitor = AttributedStringVisitor(baseFont: baseFont)
        return visitor.visit(document)
    }
}

/// Walks the swift-markdown AST and builds one NSMutableAttributedString, mirroring
/// Markwon's "single Spanned, custom spans for block constructs" approach. Only the
/// visit methods that need non-default behavior are overridden; MarkupVisitor's
/// protocol extension routes everything else through `defaultVisit`.
///
/// This is a struct (not a class) because every requirement in `MarkupVisitor` is
/// `mutating`, and value-type in-place mutation is the natural fit for the depth
/// counters (`listDepth`/`blockQuoteDepth`) that track nesting during a single
/// sequential top-to-bottom walk.
struct AttributedStringVisitor: MarkupVisitor {
    typealias Result = NSAttributedString

    private let baseFont: UIFont
    private var listDepth = 0
    private var blockQuoteDepth = 0

    init(baseFont: UIFont) {
        self.baseFont = baseFont
    }

    mutating func defaultVisit(_ markup: Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitDocument(_ document: Document) -> NSAttributedString {
        joinBlocks(Array(document.children))
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in paragraph.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in heading.children {
            result.append(visit(child))
        }
        let size = headingFontSize(for: heading.level)
        if result.length > 0 {
            result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, range, _ in
                let font = (value as? UIFont) ?? baseFont
                var traits = font.fontDescriptor.symbolicTraits
                traits.insert(.traitBold)
                let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
                result.addAttribute(.font, value: UIFont(descriptor: descriptor, size: size), range: range)
            }
        }
        return result
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in emphasis.children {
            result.append(visit(child))
        }
        applyTrait(.traitItalic, to: result)
        return result
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in strong.children {
            result.append(visit(child))
        }
        applyTrait(.traitBold, to: result)
        return result
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in strikethrough.children {
            result.append(visit(child))
        }
        if result.length > 0 {
            result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    mutating func visitText(_ text: Text) -> NSAttributedString {
        NSAttributedString(string: text.string, attributes: [.font: baseFont])
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: baseFont])
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: baseFont])
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        return NSAttributedString(string: inlineCode.code, attributes: [
            .font: font,
            .thkInlineCodeBackground: true
        ])
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        var code = codeBlock.code
        if code.hasSuffix("\n") {
            code.removeLast()
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = 4
        paragraphStyle.paragraphSpacing = 4
        return NSAttributedString(string: code, attributes: [
            .font: font,
            .thkCodeBlockBackground: true,
            .paragraphStyle: paragraphStyle
        ])
    }

    mutating func visitLink(_ link: Link) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in link.children {
            result.append(visit(child))
        }
        if let destination = link.destination, let url = URL(string: destination), result.length > 0 {
            result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    mutating func visitImage(_ image: Image) -> NSAttributedString {
        // v0: images are not loaded. Fall back to rendering the alt text as plain text.
        let result = NSMutableAttributedString()
        for child in image.children {
            result.append(visit(child))
        }
        return result
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let depth = blockQuoteDepth + 1
        blockQuoteDepth = depth
        let result = joinBlocks(Array(blockQuote.children))
        blockQuoteDepth = depth - 1

        if result.length > 0 {
            let paragraphStyle = NSMutableParagraphStyle()
            let indent: CGFloat = 16 * CGFloat(depth)
            paragraphStyle.headIndent = indent
            paragraphStyle.firstLineHeadIndent = indent
            let fullRange = NSRange(location: 0, length: result.length)
            result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            result.addAttribute(.thkBlockQuoteBar, value: depth, range: fullRange)
        }
        return result
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        NSAttributedString(string: "\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}", attributes: [
            .font: baseFont,
            .foregroundColor: UIColor.separator
        ])
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> NSAttributedString {
        listDepth += 1
        var items: [NSAttributedString] = []
        for item in unorderedList.listItems {
            items.append(renderListItem(item, marker: "\u{2022}"))
        }
        listDepth -= 1
        return joinLines(items)
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> NSAttributedString {
        listDepth += 1
        let start = Int(orderedList.startIndex)
        var items: [NSAttributedString] = []
        for (index, item) in orderedList.listItems.enumerated() {
            items.append(renderListItem(item, marker: "\(start + index)."))
        }
        listDepth -= 1
        return joinLines(items)
    }

    mutating func visitListItem(_ listItem: ListItem) -> NSAttributedString {
        renderListItem(listItem, marker: "\u{2022}")
    }

    mutating func visitTable(_ table: Table) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)

        var rows: [[String]] = []
        var headerRow: [String] = []
        for cell in table.head.cells {
            headerRow.append(plainText(of: cell))
        }
        rows.append(headerRow)
        for row in table.body.rows {
            var bodyRow: [String] = []
            for cell in row.cells {
                bodyRow.append(plainText(of: cell))
            }
            rows.append(bodyRow)
        }

        let columnCount = rows.map(\.count).max() ?? 0
        var columnWidths = [Int](repeating: 0, count: columnCount)
        for row in rows {
            for (index, cell) in row.enumerated() {
                columnWidths[index] = max(columnWidths[index], cell.count)
            }
        }

        let lines = rows.map { row -> String in
            row.enumerated().map { index, cell in
                cell.padding(toLength: columnWidths[index], withPad: " ", startingAt: 0)
            }.joined(separator: " | ")
        }

        return NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: font,
            .thkCodeBlockBackground: true
        ])
    }

    // MARK: - Helpers

    private mutating func joinBlocks(_ children: [Markup]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for (index, child) in children.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n\n"))
            }
            result.append(visit(child))
        }
        return result
    }

    private func joinLines(_ items: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(item)
        }
        return result
    }

    private mutating func renderListItem(_ item: ListItem, marker: String) -> NSAttributedString {
        let content = joinBlocks(Array(item.children))

        let prefix: String
        if let checkbox = item.checkbox {
            prefix = checkbox == .checked ? "\u{2611} " : "\u{2610} "
        } else {
            prefix = marker + " "
        }

        let line = NSMutableAttributedString(string: prefix, attributes: [.font: baseFont])
        line.append(content)

        let indentUnit: CGFloat = 20
        let indent = indentUnit * CGFloat(max(listDepth - 1, 0))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.headIndent = indent + 16
        if line.length > 0 {
            line.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: line.length))
        }
        return line
    }

    private func applyTrait(_ trait: UIFontDescriptor.SymbolicTraits, to attrString: NSMutableAttributedString) {
        guard attrString.length > 0 else { return }
        attrString.enumerateAttribute(.font, in: NSRange(location: 0, length: attrString.length)) { value, range, _ in
            let font = (value as? UIFont) ?? baseFont
            var traits = font.fontDescriptor.symbolicTraits
            traits.insert(trait)
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
            attrString.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: range)
        }
    }

    private mutating func plainText(of markup: Markup) -> String {
        visit(markup).string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func headingFontSize(for level: Int) -> CGFloat {
        let base = baseFont.pointSize
        switch level {
        case 1: return base + 10
        case 2: return base + 7
        case 3: return base + 5
        case 4: return base + 3
        case 5: return base + 1
        default: return base
        }
    }
}
