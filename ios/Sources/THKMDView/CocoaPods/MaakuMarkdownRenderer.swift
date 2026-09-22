import UIKit
import Maaku

public final class DefaultMarkdownRenderer: MarkdownRendering {
    public var baseFont: UIFont

    public init(baseFont: UIFont = UIFont.preferredFont(forTextStyle: .body)) {
        self.baseFont = baseFont
    }

    public func render(_ markdown: String) -> NSAttributedString {
        guard let document = try? Document(text: markdown) else {
            return NSAttributedString(string: markdown, attributes: [.font: baseFont])
        }
        var visitor = MaakuAttributedStringVisitor(baseFont: baseFont)
        return visitor.visit(blocks: document.items)
    }
}

/// Walks the Maaku (cmark-gfm) AST and builds one NSMutableAttributedString, the same
/// shape as the SPM distribution's `AttributedStringVisitor` (Sources/THKMDView/SPM/
/// SwiftMarkdownRenderer.swift) — including reuse of the shared `.thkInlineCodeBackground`
/// / `.thkCodeBlockBackground` / `.thkBlockQuoteBar` attribute keys so
/// `THKBackgroundLayoutManager` paints identically regardless of which parser produced the
/// attributed string. Maaku's own `Node.attributedText(style:)` is deliberately not used —
/// it has its own styling model (`Style`/`DefaultStyle`) that doesn't share these custom
/// attributes, and using it would make the two distributions behave differently.
///
/// A struct for the same reason as the SPM visitor: no reference semantics are needed,
/// and the nesting counters (`listDepth`/`blockQuoteDepth`) mutate in place during a
/// single sequential walk.
struct MaakuAttributedStringVisitor {
    private let baseFont: UIFont
    private var listDepth = 0
    private var blockQuoteDepth = 0

    init(baseFont: UIFont) {
        self.baseFont = baseFont
    }

    mutating func visit(blocks: [Block]) -> NSAttributedString {
        joinBlocks(blocks)
    }

    // MARK: - Blocks

    private mutating func visit(block: Block) -> NSAttributedString {
        switch block {
        case let paragraph as Paragraph:
            return visit(inlines: paragraph.items)
        case let heading as Heading:
            return visitHeading(heading)
        case let codeBlock as CodeBlock:
            return visitCodeBlock(codeBlock)
        case let horizontalRule as HorizontalRule:
            return visitThematicBreak(horizontalRule)
        case let blockQuote as BlockQuote:
            return visitBlockQuote(blockQuote)
        case let unorderedList as UnorderedList:
            return visitUnorderedList(unorderedList)
        case let orderedList as OrderedList:
            return visitOrderedList(orderedList)
        case let taskItem as TasklistItem:
            return renderListItem(items: taskItem.items, prefix: taskItem.completed ? "\u{2611} " : "\u{2610} ")
        case let listItem as ListItem:
            return renderListItem(items: listItem.items, prefix: "\u{2022} ")
        case let table as Table:
            return visitTable(table)
        default:
            // Unsupported block types (HTML blocks, footnotes, plugins) are not part of
            // the v0 node-type coverage on either distribution; render nothing rather
            // than guessing at a representation.
            return NSAttributedString()
        }
    }

    private mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: visit(inlines: heading.items))
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

    private func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
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

    private func visitThematicBreak(_ thematicBreak: HorizontalRule) -> NSAttributedString {
        NSAttributedString(string: "\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}", attributes: [
            .font: baseFont,
            .foregroundColor: UIColor.separator
        ])
    }

    private mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let depth = blockQuoteDepth + 1
        blockQuoteDepth = depth
        let result = joinBlocks(blockQuote.items)
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

    private mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> NSAttributedString {
        listDepth += 1
        var items: [NSAttributedString] = []
        for item in unorderedList.items {
            items.append(visit(block: item))
        }
        listDepth -= 1
        return joinLines(items)
    }

    private mutating func visitOrderedList(_ orderedList: OrderedList) -> NSAttributedString {
        listDepth += 1
        var items: [NSAttributedString] = []
        for (index, item) in orderedList.items.enumerated() {
            if let listItem = item as? ListItem {
                items.append(renderListItem(items: listItem.items, prefix: "\(index + 1). "))
            } else if let taskItem = item as? TasklistItem {
                items.append(renderListItem(items: taskItem.items, prefix: taskItem.completed ? "\u{2611} " : "\u{2610} "))
            } else {
                items.append(visit(block: item))
            }
        }
        listDepth -= 1
        return joinLines(items)
    }

    private mutating func visitTable(_ table: Table) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)

        var rows: [[String]] = []
        rows.append(table.header.cells.map(plainText(of:)))
        for row in table.rows {
            rows.append(row.cells.map(plainText(of:)))
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

    // MARK: - Inlines

    private func visit(inlines: [Inline]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for inline in inlines {
            result.append(visit(inline: inline))
        }
        return result
    }

    private func visit(inline: Inline) -> NSAttributedString {
        switch inline {
        case let text as Text:
            return NSAttributedString(string: text.text, attributes: [.font: baseFont])
        case let emphasis as Emphasis:
            let result = NSMutableAttributedString(attributedString: visit(inlines: emphasis.items))
            applyTrait(.traitItalic, to: result)
            return result
        case let strong as Strong:
            let result = NSMutableAttributedString(attributedString: visit(inlines: strong.items))
            applyTrait(.traitBold, to: result)
            return result
        case let strikethrough as Strikethrough:
            let result = NSMutableAttributedString(attributedString: visit(inlines: strikethrough.items))
            if result.length > 0 {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: result.length))
            }
            return result
        case let inlineCode as InlineCode:
            let font = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            return NSAttributedString(string: inlineCode.code, attributes: [
                .font: font,
                .thkInlineCodeBackground: true
            ])
        case let link as Link:
            let result = NSMutableAttributedString(attributedString: visit(inlines: link.text))
            if let url = link.url, result.length > 0 {
                result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
            }
            return result
        case let image as Image:
            // v0: images are not loaded. Fall back to rendering the alt text as plain text.
            return visit(inlines: image.description)
        case is SoftBreak:
            return NSAttributedString(string: "\n", attributes: [.font: baseFont])
        case is LineBreak:
            return NSAttributedString(string: "\n", attributes: [.font: baseFont])
        default:
            return NSAttributedString()
        }
    }

    // MARK: - Helpers

    private mutating func joinBlocks(_ blocks: [Block]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n\n"))
            }
            result.append(visit(block: block))
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

    private mutating func renderListItem(items: [Block], prefix: String) -> NSAttributedString {
        let content = joinBlocks(items)

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

    private func plainText(of cell: TableCell) -> String {
        visit(inlines: cell.items).string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func headingFontSize(for level: HeadingLevel) -> CGFloat {
        let base = baseFont.pointSize
        switch level {
        case .h1: return base + 10
        case .h2: return base + 7
        case .h3: return base + 5
        case .h4: return base + 3
        case .h5: return base + 1
        default: return base
        }
    }
}
