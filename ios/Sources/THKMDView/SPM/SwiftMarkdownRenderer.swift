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
                segments.append(.text(attributed, copyableBlocks: collectCopyableBlocks(in: attributed)))
            }
            pendingBlocks = []
        }

        for child in document.children {
            if let table = child as? Table {
                flushPending()
                segments.append(.table(buildTableModel(table)))
            } else if let codeBlock = child as? CodeBlock, thkIsMermaidLanguageTag(codeBlock.language) {
                flushPending()
                segments.append(.diagram(mermaidSource: mermaidSource(from: codeBlock.code)))
            } else {
                pendingBlocks.append(child)
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

    // Collects every `.thkCopyableCodeBlock`/`.thkCopyableBlockQuote`-tagged range in a
    // finished segment's attributed string into the public `THKCopyableBlock` list `THKMDView`
    // uses to place overlay copy buttons. The two keys never overlap in a way that loses
    // information (a code block nested inside a quote keeps its own range under its own key —
    // see the keys' doc comments in MarkdownRenderer.swift), so a plain per-key enumeration
    // sorted by location is enough.
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
                result.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize * size / baseFont.pointSize), range: range)
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
        NSAttributedString(string: " ", attributes: [.font: baseFont])
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
        let result = NSMutableAttributedString(string: code, attributes: [
            .font: codeFont,
            .foregroundColor: theme.codeTextColor,
            .thkCodeBlockBackground: true,
            .thkCopyableCodeBlock: true
        ])
        applyCodeBlockParagraphStyles(to: result)
        return result
    }

    mutating func visitLink(_ link: Link) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in link.children {
            result.append(visit(child))
        }
        if let destination = link.destination, let url = URL(string: destination), result.length > 0 {
            let fullRange = NSRange(location: 0, length: result.length)
            result.addAttribute(.link, value: url, range: fullRange)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            result.addAttribute(.foregroundColor, value: theme.linkColor, range: fullRange)
        }
        return result
    }

    mutating func visitImage(_ image: Image) -> NSAttributedString {
        let altText = plainText(ofChildrenOf: image)
        guard let source = image.source, let url = URL(string: source) else {
            return NSAttributedString(string: altText, attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor])
        }
        let attachment = THKAsyncImageTextAttachment(url: url, altText: altText, theme: theme)
        return NSAttributedString(attachment: attachment)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let isOutermost = blockQuoteDepth == 0
        let depth = blockQuoteDepth + 1
        blockQuoteDepth = depth
        // joinBlocksTightly (single "\n"), not joinBlocks (a blank "\n\n" paragraph): a quote's
        // own vertical rhythm must come only from paragraphStyle.lineSpacing below (applied
        // per-line, uniformly), matching Android's separate()+QuoteInteriorLineSpacingSpan. A
        // blank paragraph between e.g. this quote's own paragraph and a nested quote would add
        // a whole extra line's height on top of that, making paragraph/nested-quote boundaries
        // visibly larger-gapped than an ordinary wrapped line — a real bug, not the intended
        // "flat +2pt everywhere" rhythm.
        let result = joinBlocksTightly(Array(blockQuote.children))
        blockQuoteDepth = depth - 1

        if result.length > 0 {
            let paragraphStyle = NSMutableParagraphStyle()
            // Match Android's left inset, bar width, and text gap at each depth.
            let indent: CGFloat = THKBlockQuoteMetrics.indentPerLevel * CGFloat(depth)
            paragraphStyle.headIndent = indent
            paragraphStyle.firstLineHeadIndent = indent
            paragraphStyle.tailIndent = -THKBlockQuoteMetrics.copyButtonGutter
            // Applied at every nesting level (not just the outermost, unlike the block-level
            // vertical padding below) so a wrapped/multi-paragraph line anywhere inside a
            // quote — nested or not — gets the same interior breathing room.
            paragraphStyle.lineSpacing = THKBlockQuoteMetrics.interiorLineSpacing
            // "If missing" only: a nested BlockQuote already stamped its own (deeper) indent
            // and bar depth on its own sub-range while `result` was being built; this must
            // not clobber that with the shallower outer depth.
            thkApplyQuoteLayout(to: result, style: paragraphStyle)
            addAttributeIfMissing(.thkBlockQuoteBar, value: depth, to: result)
            addForegroundColorIfMissing(theme.blockQuoteTextColor, to: result)
            if depth == 2 { thkAddSecondLevelQuoteSpacing(to: result) }
            // Only the outermost level gets the rounded background fill: a nested quote's own
            // recursive call already ran with isOutermost == false, so this "if missing" stamp
            // (from the outermost call, over the WHOLE joined range) is the only one that ever
            // applies it — the nested portion reads as part of one continuous background
            // instead of getting its own separately-rounded, seamed fill.
            if isOutermost {
                addAttributeIfMissing(.thkBlockQuoteBackground, value: true, to: result)
                applyBlockQuoteVerticalPadding(to: result)
                thkReserveQuoteCopyGutter(in: result)
                result.addAttribute(.thkCopyableBlockQuote, value: true, range: NSRange(location: 0, length: result.length))
            }
        }
        return result
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: [
            .font: baseFont,
            .thkThematicBreak: true
        ])
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        NSAttributedString(string: thkTrimBlockLineEndings(html.rawHTML), attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor])
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
        addForegroundColorIfMissing(isHeader ? theme.headingTextColor : theme.bodyTextColor, to: result)
        return result
    }

    // MARK: - Helpers

    private mutating func joinBlocks(_ children: [Markup]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            let rendered: NSAttributedString
            if let table = child as? Table {
                rendered = thkNestedTableText(buildTableModel(table), font: baseFont)
            } else {
                rendered = visit(child)
            }
            guard rendered.length > 0 else { continue }
            if result.length > 0 {
                // TextKit uses the terminating newline's font for line metrics.
                // An unstyled newline defaults to 12pt and clips a larger heading.
                let previousFont = result.length > 0
                    ? (result.attribute(.font, at: result.length - 1, effectiveRange: nil) as? UIFont ?? baseFont)
                    : baseFont
                result.append(NSAttributedString(string: "\n", attributes: [.font: previousFont]))
                result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
            }
            result.append(rendered)
        }
        return result
    }

    // Same shape as joinBlocks above, but joins sibling blocks with a single "\n" instead of
    // a blank "\n\n" paragraph — used only for a block quote's own children (see
    // visitBlockQuote), where Android never inserts a blank line between siblings either
    // (MarkdownSpanVisitor.separate()), relying solely on QuoteInteriorLineSpacingSpan's flat
    // per-line spacing for the whole quote's vertical rhythm.
    private mutating func joinBlocksTightly(_ children: [Markup]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            let rendered: NSAttributedString
            if let table = child as? Table {
                rendered = thkNestedTableText(buildTableModel(table), font: baseFont)
            } else {
                rendered = visit(child)
            }
            guard rendered.length > 0 else { continue }
            if result.length > 0 {
                // Keep the preceding paragraph's font metrics at its terminator.
                // A bare newline compresses large quote text to the default 12pt.
                let font = result.length > 0
                    ? (result.attribute(.font, at: result.length - 1, effectiveRange: nil) as? UIFont ?? baseFont)
                    : baseFont
                var attributes: [NSAttributedString.Key: Any] = [.font: font]
                if let style = result.attribute(.paragraphStyle, at: result.length - 1, effectiveRange: nil) {
                    attributes[.paragraphStyle] = style
                }
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            result.append(rendered)
        }
        return result
    }

    private func joinLines(_ items: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if index > 0 {
                var attributes: [NSAttributedString.Key: Any] = [.font: baseFont]
                if result.length > 0 {
                    attributes[.font] = result.attribute(.font, at: result.length - 1, effectiveRange: nil) ?? baseFont
                    attributes[.paragraphStyle] = result.attribute(.paragraphStyle, at: result.length - 1, effectiveRange: nil)
                }
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            result.append(item)
        }
        return result
    }

    private mutating func renderListItem(_ item: ListItem, marker: String) -> NSAttributedString {
        let content = joinBlocksTightly(Array(item.children))

        let line = NSMutableAttributedString()
        if let checkbox = item.checkbox {
            line.append(thkCheckboxPrefixAttributedString(checked: checkbox == .checked, font: baseFont, color: theme.bodyTextColor))
        } else {
            line.append(NSAttributedString(string: marker + " ", attributes: [.font: baseFont, .foregroundColor: theme.bodyTextColor]))
        }
        line.append(content)

        thkApplyListLayout(to: line, prefixLength: line.length - content.length, depth: listDepth)
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
        if trait == .traitItalic {
            THKEmphasisStyling.applyCJKFallback(to: attrString)
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
            paragraphStyle.tailIndent = -THKCodeBlockMetrics.copyButtonGutter
            paragraphStyle.paragraphSpacingBefore = index == 0 ? THKCodeBlockMetrics.verticalPaddingTop : 0
            paragraphStyle.paragraphSpacing = index == paragraphRanges.count - 1 ? THKCodeBlockMetrics.verticalPaddingBottom : 0
            attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
    }

    // Block-level top/bottom padding for the OUTERMOST quote only (matches Android's
    // ThemedQuoteSpan.chooseHeight, which is only active when its backgroundColor is
    // non-nil — i.e. only the outermost span). Unlike `applyCodeBlockParagraphStyles`, this
    // must not replace the paragraphStyle already set on the first/last paragraph (which may
    // belong to a nested quote's own deeper indent/lineSpacing) — it copies whatever style is
    // already there and only adds spacingBefore/spacingAfter to it.
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
            style.paragraphSpacingBefore += before
            style.paragraphSpacing += after
            attrString.addAttribute(.paragraphStyle, value: style, range: range)
        }

        if first == last {
            addSpacing(to: first, before: THKBlockQuoteMetrics.verticalPaddingTop, after: THKBlockQuoteMetrics.verticalPaddingBottom)
        } else {
            addSpacing(to: first, before: THKBlockQuoteMetrics.verticalPaddingTop, after: 0)
            addSpacing(to: last, before: 0, after: THKBlockQuoteMetrics.verticalPaddingBottom)
        }
    }

    private mutating func plainText(of markup: Markup) -> String {
        visit(markup).string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func plainText(ofChildrenOf markup: Markup) -> String {
        markup.children.map { plainText(of: $0) }.joined()
    }

    // Relative multipliers matching Android's `sizeForLevel` in MarkdownSpanVisitor.kt, so
    // the h1-h6 size ramp looks the same on both platforms regardless of the theme's
    // bodyFontSize (a fixed-point-offset ramp, used previously, drifts away from Android's
    // ratios whenever bodyFontSize differs from the value it was tuned against).
    private func headingFontSize(for level: Int) -> CGFloat {
        baseFont.pointSize * headingSizeRatio(for: level)
    }

    private func headingSizeRatio(for level: Int) -> CGFloat {
        switch level {
        case 1: return theme.heading1Scale
        case 2: return theme.heading2Scale
        case 3: return theme.heading3Scale
        case 4: return theme.heading4Scale
        case 5: return theme.heading5Scale
        default: return theme.heading6Scale
        }
    }
}
