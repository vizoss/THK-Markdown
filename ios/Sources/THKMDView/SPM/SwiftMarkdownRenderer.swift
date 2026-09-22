import UIKit
import Markdown

public final class DefaultMarkdownRenderer: MarkdownRendering {
    public var baseFont: UIFont
    public var theme: THKMDTheme

    public init(baseFont: UIFont = UIFont.preferredFont(forTextStyle: .body), theme: THKMDTheme = .default) {
        self.baseFont = baseFont
        self.theme = theme
    }

    public func render(_ markdown: String) -> [THKRenderSegment] {
        let document = Document(parsing: markdown)
        var visitor = AttributedStringVisitor(baseFont: baseFont, theme: theme)
        return visitor.renderSegments(document)
    }
}

/// Walks the swift-markdown AST and builds a sequence of `THKRenderSegment`s, mirroring
/// Markwon's "one Spanned, custom spans for block constructs" approach for everything except
/// `Table`, which becomes its own segment (see `THKRenderSegment`). Only the visit methods
/// that need non-default behavior are overridden; MarkupVisitor's protocol extension routes
/// everything else through `defaultVisit`.
///
/// This is a struct (not a class) because every requirement in `MarkupVisitor` is `mutating`,
/// and value-type in-place mutation is the natural fit for the depth counters
/// (`listDepth`/`blockQuoteDepth`) that track nesting during a single sequential walk.
struct AttributedStringVisitor: MarkupVisitor {
    typealias Result = NSAttributedString

    private let baseFont: UIFont
    private let theme: THKMDTheme
    private var listDepth = 0
    private var blockQuoteDepth = 0

    init(baseFont: UIFont, theme: THKMDTheme) {
        // theme.bodyFontSize governs the effective body text size; baseFont still controls
        // family/weight, so a caller-supplied baseFont's typeface is preserved.
        self.baseFont = UIFont(descriptor: baseFont.fontDescriptor, size: theme.bodyFontSize)
        self.theme = theme
    }

    private var codeFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: theme.codeFontSize, weight: .regular)
    }

    mutating func defaultVisit(_ markup: Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(visit(child))
        }
        return result
    }

    // MARK: - Top-level: split into segments at each Table

    mutating func renderSegments(_ document: Document) -> [THKRenderSegment] {
        var segments: [THKRenderSegment] = []
        var pendingBlocks: [Markup] = []

        func flushPending() {
            guard !pendingBlocks.isEmpty else { return }
            let attributed = joinBlocks(pendingBlocks)
            if attributed.length > 0 {
                addForegroundColorIfMissing(theme.bodyTextColor, to: attributed)
                segments.append(.text(attributed))
            }
            pendingBlocks = []
        }

        for child in document.children {
            if let table = child as? Table {
                flushPending()
                segments.append(.table(buildTableModel(table)))
            } else {
                pendingBlocks.append(child)
            }
        }
        flushPending()
        return segments
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
        addForegroundColorIfMissing(theme.headingTextColor, to: result)
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

    // No default foreground color here: color is filled in bottom-up by the nearest
    // "coloring" ancestor (link/inline code directly; heading/block quote/table cell/the
    // top-level segment only where a more specific color isn't already present), so a link
    // or inline code span nested inside a heading or block quote keeps its own color.
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
        NSAttributedString(string: inlineCode.code, attributes: [
            .font: codeFont,
            .foregroundColor: theme.codeTextColor,
            .thkInlineCodeBackground: true
        ])
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") {
            code.removeLast()
        }
        return NSAttributedString(string: code, attributes: [
            .font: codeFont,
            .foregroundColor: theme.codeTextColor,
            .thkCodeBlockBackground: true,
            .paragraphStyle: codeBlockParagraphStyle()
        ])
    }

    mutating func visitLink(_ link: Link) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in link.children {
            result.append(visit(child))
        }
        if let destination = link.destination, let url = URL(string: destination), result.length > 0 {
            let fullRange = NSRange(location: 0, length: result.length)
            result.addAttribute(.link, value: url, range: fullRange)
            result.addAttribute(.foregroundColor, value: theme.linkColor, range: fullRange)
        }
        return result
    }

    mutating func visitImage(_ image: Image) -> NSAttributedString {
        let altText = plainText(ofChildrenOf: image)
        guard let source = image.source, let url = URL(string: source) else {
            return NSAttributedString(string: altText, attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor])
        }
        let attachment = THKAsyncImageTextAttachment(url: url, altText: altText)
        return NSAttributedString(attachment: attachment)
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
            // "If missing" only: a nested BlockQuote already stamped its own (deeper) indent
            // and bar depth on its own sub-range while `result` was being built; this must
            // not clobber that with the shallower outer depth.
            addAttributeIfMissing(.paragraphStyle, value: paragraphStyle, to: result)
            addAttributeIfMissing(.thkBlockQuoteBar, value: depth, to: result)
            addForegroundColorIfMissing(theme.blockQuoteTextColor, to: result)
        }
        return result
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        NSAttributedString(string: "\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}\u{2015}", attributes: [
            .font: baseFont,
            .foregroundColor: UIColor.separator
        ])
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        NSAttributedString(string: html.rawHTML, attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor])
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSAttributedString {
        NSAttributedString(string: inlineHTML.rawHTML, attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor])
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

    // MARK: - Tables (own segment, not attributed-string flow)

    private mutating func buildTableModel(_ table: Table) -> THKTableModel {
        let alignments = table.columnAlignments.map { alignment -> THKTableColumnAlignment in
            switch alignment {
            case .some(.center): return .center
            case .some(.right): return .trailing
            default: return .leading
            }
        }
        var headerCells: [NSAttributedString] = []
        for cell in table.head.cells {
            headerCells.append(cellAttributedString(cell, isHeader: true))
        }
        var rows: [[NSAttributedString]] = []
        for row in table.body.rows {
            var rowCells: [NSAttributedString] = []
            for cell in row.cells {
                rowCells.append(cellAttributedString(cell, isHeader: false))
            }
            rows.append(rowCells)
        }
        return THKTableModel(alignments: alignments, headerCells: headerCells, rows: rows)
    }

    // Shared with the normal block flow: a table cell's inline Markdown goes through the same
    // per-inline-node `visit` dispatch used for paragraphs/list items, not a plain-text shortcut.
    private mutating func cellAttributedString(_ cell: Table.Cell, isHeader: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in cell.children {
            result.append(visit(child))
        }
        if isHeader, result.length > 0 {
            applyTrait(.traitBold, to: result)
        }
        addForegroundColorIfMissing(theme.bodyTextColor, to: result)
        return result
    }

    // MARK: - Helpers

    private mutating func joinBlocks(_ children: [Markup]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for (index, child) in children.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n\n"))
            }
            if let table = child as? Table {
                // A Table that ends up here (nested inside a block quote/list item, where it
                // cannot become its own segment) falls back to being rendered inline as its
                // header/first-row plain text isn't meaningful in that position, so render
                // nothing rather than guessing — top-level tables are the supported case.
                _ = table
                continue
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

        let line = NSMutableAttributedString(string: prefix, attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor])
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

    // Fills in `color` only where no `.foregroundColor` is already set, so a more specific
    // inner color (e.g. a link or inline code inside a heading/block quote) is preserved.
    private func addForegroundColorIfMissing(_ color: UIColor, to attrString: NSMutableAttributedString) {
        addAttributeIfMissing(.foregroundColor, value: color, to: attrString)
    }

    // Fills in `value` for `key` only where that attribute isn't already set, so a nested
    // block quote's own (more specific) value — indent, bar depth, color — set while
    // building its own sub-range isn't clobbered when the enclosing quote stamps its value
    // across the full joined range.
    private func addAttributeIfMissing(_ key: NSAttributedString.Key, value: Any, to attrString: NSMutableAttributedString) {
        guard attrString.length > 0 else { return }
        var rangesNeedingValue: [NSRange] = []
        attrString.enumerateAttribute(key, in: NSRange(location: 0, length: attrString.length)) { existing, range, _ in
            if existing == nil {
                rangesNeedingValue.append(range)
            }
        }
        for range in rangesNeedingValue {
            attrString.addAttribute(key, value: value, range: range)
        }
    }

    private func codeBlockParagraphStyle() -> NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = 4
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.firstLineHeadIndent = THKCodeBlockMetrics.horizontalPadding
        paragraphStyle.headIndent = THKCodeBlockMetrics.horizontalPadding
        paragraphStyle.tailIndent = -THKCodeBlockMetrics.horizontalPadding
        return paragraphStyle
    }

    private mutating func plainText(of markup: Markup) -> String {
        visit(markup).string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func plainText(ofChildrenOf markup: Markup) -> String {
        markup.children.map { plainText(of: $0) }.joined()
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
