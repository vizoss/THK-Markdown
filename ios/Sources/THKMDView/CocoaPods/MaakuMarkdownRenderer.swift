import UIKit
import Maaku

public final class DefaultMarkdownRenderer: MarkdownRendering {
    public var baseFont: UIFont
    public var theme: THKMDTheme

    public init(baseFont: UIFont = UIFont.preferredFont(forTextStyle: .body), theme: THKMDTheme = .default) {
        self.baseFont = baseFont
        self.theme = theme
    }

    public func render(_ markdown: String) -> [THKRenderSegment] {
        guard let document = try? Document(text: markdown) else {
            return [.text(NSAttributedString(string: markdown, attributes: [.font: baseFont]), copyableBlocks: [])]
        }
        var visitor = MaakuAttributedStringVisitor(baseFont: baseFont, theme: theme)
        return visitor.renderSegments(blocks: document.items)
    }
}

/// Walks the Maaku (cmark-gfm) AST and builds a sequence of `THKRenderSegment`s, the same
/// shape as the SPM distribution's `AttributedStringVisitor` (Sources/THKMDView/SPM/
/// SwiftMarkdownRenderer.swift) — including reuse of the shared `.thkInlineCodeBackground`
/// / `.thkCodeBlockBackground` / `.thkBlockQuoteBar` attribute keys so
/// `THKBackgroundLayoutManager` paints identically regardless of which parser produced the
/// attributed string, and the same `THKTableModel`/`THKRenderSegment` split at each top-level
/// `Table` block. Maaku's own `Node.attributedText(style:)` is deliberately not used — it has
/// its own styling model (`Style`/`DefaultStyle`) that doesn't share these custom attributes
/// or the theme, and using it would make the two distributions behave differently.
///
/// A struct for the same reason as the SPM visitor: no reference semantics are needed, and the
/// nesting counters (`listDepth`/`blockQuoteDepth`) mutate in place during a single sequential
/// walk.
struct MaakuAttributedStringVisitor {
    private let baseFont: UIFont
    private let theme: THKMDTheme
    private var listDepth = 0
    private var blockQuoteDepth = 0

    init(baseFont: UIFont, theme: THKMDTheme) {
        self.baseFont = UIFont(descriptor: baseFont.fontDescriptor, size: theme.bodyFontSize)
        self.theme = theme
    }

    private var codeFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: theme.codeFontSize, weight: .regular)
    }

    // MARK: - Top-level: split into segments at each Table

    mutating func renderSegments(blocks: [Block]) -> [THKRenderSegment] {
        var segments: [THKRenderSegment] = []
        var pendingBlocks: [Block] = []

        func flushPending() {
            guard !pendingBlocks.isEmpty else { return }
            let attributed = joinBlocks(pendingBlocks)
            if attributed.length > 0 {
                addForegroundColorIfMissing(theme.bodyTextColor, to: attributed)
                segments.append(.text(attributed, copyableBlocks: collectCopyableBlocks(in: attributed)))
            }
            pendingBlocks = []
        }

        for block in blocks {
            if let table = block as? Table {
                flushPending()
                segments.append(.table(buildTableModel(table)))
            } else if let codeBlock = block as? CodeBlock, thkIsMermaidLanguageTag(codeBlock.info) {
                flushPending()
                segments.append(.diagram(mermaidSource: mermaidSource(from: codeBlock.code)))
            } else {
                pendingBlocks.append(block)
            }
        }
        flushPending()
        return segments
    }

    private func mermaidSource(from code: String) -> String {
        var source = code
        if source.hasSuffix("\n") {
            source.removeLast()
        }
        return source
    }

    // Mirrors the SPM renderer's identically-named helper — see its doc comment in
    // Sources/THKMDView/SPM/SwiftMarkdownRenderer.swift.
    private func collectCopyableBlocks(in attributed: NSAttributedString) -> [THKCopyableBlock] {
        guard attributed.length > 0 else { return [] }
        let fullRange = NSRange(location: 0, length: attributed.length)
        let nsString = attributed.string as NSString
        var found: [(NSRange, String)] = []
        for key in [NSAttributedString.Key.thkCopyableCodeBlock, .thkCopyableBlockQuote] {
            attributed.enumerateAttribute(key, in: fullRange) { value, range, _ in
                guard value != nil, range.length > 0 else { return }
                found.append((range, nsString.substring(with: range)))
            }
        }
        return found.sorted { $0.0.location < $1.0.location }.map { THKCopyableBlock(range: $0.0, text: $0.1) }
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
        case let htmlBlock as HtmlBlock:
            return NSAttributedString(string: htmlBlock.html, attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor])
        case is Table:
            // A Table nested inside a block quote/list item (not top-level) can't become its
            // own segment here, so it's skipped rather than guessing at an inline representation.
            return NSAttributedString()
        default:
            // Unsupported block types (footnotes, plugins) are not part of the node-type
            // coverage on either distribution; render nothing rather than guessing.
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
        addForegroundColorIfMissing(theme.headingTextColor, to: result)
        return result
    }

    private func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") {
            code.removeLast()
        }
        let result = NSMutableAttributedString(string: code, attributes: [
            .font: codeFont,
            .foregroundColor: theme.codeTextColor,
            .thkCodeBlockBackground: true,
            .thkCopyableCodeBlock: true
        ])
        applyCodeBlockParagraphStyles(to: result)
        return result
    }

    private func visitThematicBreak(_ thematicBreak: HorizontalRule) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: [
            .font: baseFont,
            .thkThematicBreak: true
        ])
    }

    private mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let isOutermost = blockQuoteDepth == 0
        let depth = blockQuoteDepth + 1
        blockQuoteDepth = depth
        let result = joinBlocks(blockQuote.items)
        blockQuoteDepth = depth - 1

        if result.length > 0 {
            let paragraphStyle = NSMutableParagraphStyle()
            // Bar width + bar-to-text gap per level, not one opaque constant — see
            // THKBlockQuoteMetrics. Numerically unchanged from the previous single `16 *
            // depth` (4 + 12 == 16), so this is a naming/composition change, not a layout one.
            let indent: CGFloat = THKBlockQuoteMetrics.indentPerLevel * CGFloat(depth)
            paragraphStyle.headIndent = indent
            paragraphStyle.firstLineHeadIndent = indent
            // Applied at every nesting level (not just the outermost, unlike the block-level
            // vertical padding below) so a wrapped/multi-paragraph line anywhere inside a
            // quote — nested or not — gets the same interior breathing room.
            paragraphStyle.lineSpacing = THKBlockQuoteMetrics.interiorLineSpacing
            // "If missing" only: a nested BlockQuote already stamped its own (deeper) indent
            // and bar depth on its own sub-range while `result` was being built; this must
            // not clobber that with the shallower outer depth.
            addAttributeIfMissing(.paragraphStyle, value: paragraphStyle, to: result)
            addAttributeIfMissing(.thkBlockQuoteBar, value: depth, to: result)
            addForegroundColorIfMissing(theme.blockQuoteTextColor, to: result)
            // Only the outermost level gets the rounded background fill: a nested quote's own
            // recursive call already ran with isOutermost == false, so this "if missing" stamp
            // (from the outermost call, over the WHOLE joined range) is the only one that ever
            // applies it — the nested portion reads as part of one continuous background
            // instead of getting its own separately-rounded, seamed fill.
            if isOutermost {
                addAttributeIfMissing(.thkBlockQuoteBackground, value: true, to: result)
                applyBlockQuoteVerticalPadding(to: result)
                result.addAttribute(.thkCopyableBlockQuote, value: true, range: NSRange(location: 0, length: result.length))
            }
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

    // MARK: - Tables (own segment, not attributed-string flow)

    private mutating func buildTableModel(_ table: Table) -> THKTableModel {
        let alignments: [THKTableColumnAlignment]
        if table.alignments.isEmpty {
            let columnCount = max(table.columns, table.header.cells.count)
            alignments = Array(repeating: .leading, count: columnCount)
        } else {
            alignments = table.alignments.map { alignment -> THKTableColumnAlignment in
                switch alignment {
                case .center: return .center
                case .right: return .trailing
                default: return .leading
                }
            }
        }
        let headerCells = table.header.cells.map { cellAttributedString($0, isHeader: true) }
        let rows = table.rows.map { row in
            row.cells.map { cellAttributedString($0, isHeader: false) }
        }
        return THKTableModel(alignments: alignments, headerCells: headerCells, rows: rows)
    }

    // Shared with the normal block flow: a table cell's inline Markdown goes through the same
    // per-inline-node `visit` dispatch used for paragraphs/list items, not a plain-text shortcut.
    private func cellAttributedString(_ cell: TableCell, isHeader: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: visit(inlines: cell.items))
        if isHeader, result.length > 0 {
            applyTrait(.traitBold, to: result)
        }
        addForegroundColorIfMissing(theme.bodyTextColor, to: result)
        return result
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
            // No default foreground color: color is filled in bottom-up by the nearest
            // "coloring" ancestor (link/inline code directly; heading/block quote/table
            // cell/the top-level segment only where a more specific color isn't already
            // present), so a link or inline code span nested inside a heading or block
            // quote keeps its own color.
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
            return NSAttributedString(string: inlineCode.code, attributes: [
                .font: codeFont,
                .foregroundColor: theme.codeTextColor,
                .thkInlineCodeBackground: true
            ])
        case let link as Link:
            let result = NSMutableAttributedString(attributedString: visit(inlines: link.text))
            if let url = link.url, result.length > 0 {
                let fullRange = NSRange(location: 0, length: result.length)
                result.addAttribute(.link, value: url, range: fullRange)
                result.addAttribute(.foregroundColor, value: theme.linkColor, range: fullRange)
            }
            return result
        case let image as Image:
            let altText = visit(inlines: image.description).string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = image.url else {
                return NSAttributedString(string: altText, attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor])
            }
            let attachment = THKAsyncImageTextAttachment(url: url, altText: altText)
            return NSAttributedString(attachment: attachment)
        case let inlineHtml as InlineHtml:
            return NSAttributedString(string: inlineHtml.html, attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor])
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

    // A single NSParagraphStyle applied uniformly across a multi-line code block would add
    // paragraphSpacingBefore/paragraphSpacing at every internal line break too, since each
    // `\n`-delimited line is its own "paragraph" for NSParagraphStyle purposes — that would
    // put unwanted gaps between every source line, not just around the block's outside. So
    // each line/paragraph range gets its own style object, with the vertical padding
    // non-zero only on the very first (spacingBefore) and very last (spacing) line.
    private func applyCodeBlockParagraphStyles(to attrString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attrString.length)
        guard fullRange.length > 0 else { return }
        var paragraphRanges: [NSRange] = []
        (attrString.string as NSString).enumerateSubstrings(in: fullRange, options: .byParagraphs) { _, _, enclosingRange, _ in
            paragraphRanges.append(enclosingRange)
        }
        guard !paragraphRanges.isEmpty else { return }
        for (index, range) in paragraphRanges.enumerated() {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = THKCodeBlockMetrics.horizontalPadding
            paragraphStyle.headIndent = THKCodeBlockMetrics.horizontalPadding
            paragraphStyle.tailIndent = -THKCodeBlockMetrics.horizontalPadding
            paragraphStyle.paragraphSpacingBefore = index == 0 ? THKCodeBlockMetrics.verticalPadding : 0
            paragraphStyle.paragraphSpacing = index == paragraphRanges.count - 1 ? THKCodeBlockMetrics.verticalPadding : 0
            attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
    }

    // Mirrors the SPM renderer's identically-named helper — see its doc comment in
    // Sources/THKMDView/SPM/SwiftMarkdownRenderer.swift.
    private func applyBlockQuoteVerticalPadding(to attrString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attrString.length)
        guard fullRange.length > 0 else { return }
        var paragraphRanges: [NSRange] = []
        (attrString.string as NSString).enumerateSubstrings(in: fullRange, options: .byParagraphs) { _, _, enclosingRange, _ in
            paragraphRanges.append(enclosingRange)
        }
        guard let first = paragraphRanges.first, let last = paragraphRanges.last else { return }

        func addSpacing(to range: NSRange, before: CGFloat, after: CGFloat) {
            guard range.length > 0 else { return }
            let existing = (attrString.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle.default
            let style = (existing.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            attrString.addAttribute(.paragraphStyle, value: style, range: range)
        }

        if first == last {
            addSpacing(to: first, before: THKBlockQuoteMetrics.verticalPadding, after: THKBlockQuoteMetrics.verticalPadding)
        } else {
            addSpacing(to: first, before: THKBlockQuoteMetrics.verticalPadding, after: 0)
            addSpacing(to: last, before: 0, after: THKBlockQuoteMetrics.verticalPadding)
        }
    }

    // Relative multipliers matching Android's `sizeForLevel` in MarkdownSpanVisitor.kt, so
    // the h1-h6 size ramp looks the same on both platforms regardless of the theme's
    // bodyFontSize (a fixed-point-offset ramp, used previously, drifts away from Android's
    // ratios whenever bodyFontSize differs from the value it was tuned against).
    private func headingFontSize(for level: HeadingLevel) -> CGFloat {
        baseFont.pointSize * Self.headingSizeRatio(for: level)
    }

    private static func headingSizeRatio(for level: HeadingLevel) -> CGFloat {
        switch level {
        case .h1: return 1.6
        case .h2: return 1.4
        case .h3: return 1.25
        case .h4: return 1.15
        case .h5: return 1.05
        default: return 1.0
        }
    }
}
