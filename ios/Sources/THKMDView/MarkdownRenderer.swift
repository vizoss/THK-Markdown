import UIKit

/// Copy formula source rather than the attachment's U+FFFC placeholder.
func thkCopyText(_ text: NSAttributedString, range: NSRange) -> String {
    let part = text.attributedSubstring(from: range)
    let output = NSMutableString(string: part.string)
    part.enumerateAttribute(.attachment, in: NSRange(location: 0, length: part.length), options: .reverse) { value, range, _ in
        if let attachment = value as? THKAsyncImageTextAttachment, let source = THKMathEngine.source(attachment.url) {
            output.replaceCharacters(in: range, with: source)
        }
    }
    return output as String
}

private let thkListDepthKey = NSAttributedString.Key("THKListDepth")

/// Block separators belong to the joining layer; retain interior HTML whitespace.
func thkTrimBlockLineEndings(_ source: String) -> String {
    var result = source
    while result.last == "\n" || result.last == "\r" || result.last == "\r\n" { result.removeLast() }
    return result
}
let thkQuoteContainerIndentKey = NSAttributedString.Key("THKQuoteContainerIndent")

/// Keep child list styles intact; add the current list offset to other block styles.
func thkApplyListLayout(to text: NSMutableAttributedString, prefixLength: Int, depth: Int) {
    guard text.length > 0 else { return }
    let indent = CGFloat(max(0, depth - 1)) * 20
    let markerWidth = text.attributedSubstring(from: NSRange(location: 0, length: prefixLength)).size().width
    let contentIndent = indent + markerWidth
    let full = NSRange(location: 0, length: text.length)
    var paragraphs: [NSRange] = []
    (text.string as NSString).enumerateSubstrings(in: full, options: .byParagraphs) { _, _, range, _ in paragraphs.append(range) }
    for range in paragraphs {
        // The marker prefix has no depth attribute. Inspect the actual content.
        let probe = range.location == 0 ? min(prefixLength, text.length - 1) : range.location
        if let existingDepth = text.attribute(thkListDepthKey, at: probe, effectiveRange: nil) as? Int, existingDepth > depth { continue }
        let existing = text.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle
        let style = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        if existing != nil {
            style.firstLineHeadIndent += contentIndent
            style.headIndent += contentIndent
            if text.attribute(.thkBlockQuoteBar, at: probe, effectiveRange: nil) != nil {
                let prior = text.attribute(thkQuoteContainerIndentKey, at: probe, effectiveRange: nil) as? CGFloat ?? 0
                text.addAttribute(thkQuoteContainerIndentKey, value: prior + contentIndent, range: range)
            }
        } else {
            style.firstLineHeadIndent = range.location == 0 ? indent : contentIndent
            style.headIndent = contentIndent
        }
        text.addAttributes([.paragraphStyle: style, thkListDepthKey: depth], range: range)
    }
}

func thkApplyQuoteLayout(to text: NSMutableAttributedString, style: NSParagraphStyle) {
    let full = NSRange(location: 0, length: text.length)
    text.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
        // Descendant quotes already have an absolute depth. Other child blocks need
        // their existing indent/padding preserved inside this quote's indentation.
        if text.attribute(.thkBlockQuoteBar, at: range.location, effectiveRange: nil) != nil { return }
        let combined = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        combined.headIndent += style.headIndent
        combined.firstLineHeadIndent += style.firstLineHeadIndent
        combined.tailIndent = min(combined.tailIndent, style.tailIndent)
        combined.lineSpacing = max(combined.lineSpacing, style.lineSpacing)
        text.addAttribute(.paragraphStyle, value: combined, range: range)
    }
    // TextKit's lineSpacing does not separate distinct paragraphs. Give each
    // interior paragraph the same breathing room as a wrapped line. Use max,
    // not +=, because the outer quote visits nested paragraphs again.
    var paragraphs: [NSRange] = []
    (text.string as NSString).enumerateSubstrings(in: full, options: .byParagraphs) { _, _, range, _ in
        paragraphs.append(range)
    }
    for range in paragraphs.dropLast() {
        let existing = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let paragraph = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraph.paragraphSpacing = max(paragraph.paragraphSpacing, style.lineSpacing)
        text.addAttribute(.paragraphStyle, value: paragraph, range: range)
    }
}

func thkNestedTableText(_ table: THKTableModel, font: UIFont) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (rowIndex, row) in ([table.headerCells] + table.rows).enumerated() {
        if rowIndex > 0 { result.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
        for (index, cell) in row.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: " | ", attributes: [.font: font])) }
            result.append(cell)
        }
    }
    return result
}

/// Nested copyable blocks share a wider gutter, including when they start on one line.
func thkReserveQuoteCopyGutter(in text: NSMutableAttributedString) {
    let full = NSRange(location: 0, length: text.length)
    guard full.length > 0 else { return }
    var hasCode = false
    text.enumerateAttribute(.thkCopyableCodeBlock, in: full) { value, _, _ in if value != nil { hasCode = true } }
    let startsWithCode = text.attribute(.thkCopyableCodeBlock, at: 0, effectiveRange: nil) != nil
    let gutter: CGFloat = hasCode ? (startsWithCode ? 84 : 48) : 40
    text.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
        let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.tailIndent = min(style.tailIndent, -gutter)
        text.addAttribute(.paragraphStyle, value: style, range: range)
    }
}

/// A renderer walks Markdown text into an ordered list of segments (see `THKRenderSegment`)
/// instead of one attributed string, so a `Table` block can become its own horizontally
/// scrollable view. `theme` is settable independently of `render(_:)` so `THKMDView` can
/// change colors/sizes without re-instantiating the renderer.
public protocol MarkdownRendering: AnyObject {
    var theme: THKMDTheme { get set }
    func render(_ markdown: String) -> [THKRenderSegment]
}

/// One block-level chunk of rendered output. As many consecutive non-table top-level blocks
/// as possible are merged into a single `.text` segment (unchanged from the v0 "one
/// NSAttributedString" model); a `Table` block always becomes its own `.table` segment, since
/// it needs a real, independently hit-testable, horizontally scrollable view. A fenced code
/// block tagged ```mermaid``` becomes its own `.diagram` segment instead of a normal code
/// block, rendered by `THKMermaidView` (see that file).
public enum THKRenderSegment {
    case text(NSAttributedString, copyableBlocks: [THKCopyableBlock])
    case table(THKTableModel)
    case diagram(mermaidSource: String)
}

/// A tappable-to-copy range within a `.text` segment's attributed string: a fenced/indented
/// code block, or an outermost block quote (see `.thkCopyableCodeBlock`/`.thkCopyableBlockQuote`
/// below — only the outermost level of a nested `> > quote` gets one, mirroring
/// `.thkBlockQuoteBackground`). `text` is the plain display text for that range, exactly what
/// `UIPasteboard.general.string` should be set to on tap.
public struct THKCopyableBlock {
    public let range: NSRange
    public let text: String

    public init(range: NSRange, text: String) {
        self.range = range
        self.text = text
    }
}

public enum THKTableColumnAlignment {
    case leading
    case center
    case trailing
}

/// A GFM table's structure: each cell is its own attributed string (built through the same
/// inline-markdown helper used for paragraph text), since GFM table cells can contain inline
/// Markdown (bold, links, code, ...).
public struct THKTableModel {
    public let alignments: [THKTableColumnAlignment]
    public let headerCells: [NSAttributedString]
    public let rows: [[NSAttributedString]]

    public init(alignments: [THKTableColumnAlignment], headerCells: [NSAttributedString], rows: [[NSAttributedString]]) {
        self.alignments = alignments
        self.headerCells = headerCells
        self.rows = rows
    }
}

public extension NSAttributedString.Key {
    /// Paints a rounded background behind inline `code` spans. No built-in
    /// NSAttributedString attribute does this, so THKBackgroundLayoutManager reads it.
    static let thkInlineCodeBackground = NSAttributedString.Key("THKInlineCodeBackground")
    /// Paints a full-width background behind fenced/indented code blocks.
    static let thkCodeBlockBackground = NSAttributedString.Key("THKCodeBlockBackground")
    /// Paints a left-edge vertical bar behind block quote ranges. Value is the nesting depth (Int).
    static let thkBlockQuoteBar = NSAttributedString.Key("THKBlockQuoteBar")
    /// Paints a full-width rounded background behind a block quote range. Only set on the
    /// outermost level of a nested `> > quote` (see `blockQuoteDepth` in each renderer), so a
    /// nested quote reads as one continuous background rather than a seam where the nested
    /// portion starts.
    static let thkBlockQuoteBackground = NSAttributedString.Key("THKBlockQuoteBackground")
    /// Draws a real filled rect (not a glyph run) spanning a thematic break's line, at
    /// vertical center — see `drawThematicBreak` in THKBackgroundLayoutManager.swift for why
    /// this replaced a run of `\u{2015}` characters (font-dependent side-bearing made that
    /// render visibly dashed in some fonts). Set on a single placeholder character.
    static let thkThematicBreak = NSAttributedString.Key("THKThematicBreak")
    /// Marks a fenced/indented code block's full range as copy-button-eligible (see
    /// `THKCopyableBlock`). Set directly on the code block's own range — never touched by an
    /// enclosing block quote's own (different) key below, so a code block nested inside a
    /// quote keeps its own independent copy range.
    static let thkCopyableCodeBlock = NSAttributedString.Key("THKCopyableCodeBlock")
    /// Marks an outermost block quote's full range (nested quote text included) as
    /// copy-button-eligible. Only ever set by the outermost `visitBlockQuote` call, same
    /// "only the outermost gets it" rule as `.thkBlockQuoteBackground`.
    static let thkCopyableBlockQuote = NSAttributedString.Key("THKCopyableBlockQuote")
}

/// Shared block-quote layout constants, numerically identical to Android's
/// `MarkdownSpanVisitor.QUOTE_BAR_WIDTH_DP`/`QUOTE_BAR_GAP_DP`/`QUOTE_INTERIOR_LINE_SPACING_DP`
/// (dp ≈ pt at baseline scale). Each level reserves a left inset, the bar, and a text gap.
enum THKBlockQuoteMetrics {
    static let barWidth: CGFloat = 4
    static let barLeftInset: CGFloat = 8
    static let barToTextGap: CGFloat = 8
    static let secondLevelTopSpacing: CGFloat = 10
    static let secondLevelBottomSpacing: CGFloat = 10
    static let indentPerLevel: CGFloat = barLeftInset + barWidth + barToTextGap
    /// Extra breathing room between wrapped/multi-paragraph lines *inside* a quote, on top of
    /// (not instead of) the block-level top/bottom padding below.
    static let interiorLineSpacing: CGFloat = 2
    /// Bottom-of-last-line padding for the whole (outermost) quote block — shared with
    /// `THKCodeBlockMetrics.verticalPaddingBottom` so both "padded block" types read as one
    /// consistent family, matching Android's shared `BLOCK_VERTICAL_PADDING_DP`.
    static let verticalPaddingBottom: CGFloat = THKCodeBlockMetrics.verticalPaddingBottom
    /// Copy buttons sit beside the text in a trailing gutter.
    static let verticalPaddingTop: CGFloat = 8
    static let copyButtonGutter: CGFloat = 40
}

/// Add space around the whole second-level quote, not between its paragraphs.
func thkAddSecondLevelQuoteSpacing(to text: NSMutableAttributedString) {
    guard text.length > 0 else { return }
    let range = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
    let existing = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    let style = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
    style.paragraphSpacingBefore += THKBlockQuoteMetrics.secondLevelTopSpacing
    text.addAttribute(.paragraphStyle, value: style, range: range)
    let lastRange = (text.string as NSString).paragraphRange(for: NSRange(location: text.length - 1, length: 0))
    let lastStyle = text.attribute(.paragraphStyle, at: lastRange.location, effectiveRange: nil) as? NSParagraphStyle
    let bottomStyle = lastStyle?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
    bottomStyle.paragraphSpacing = max(bottomStyle.paragraphSpacing, THKBlockQuoteMetrics.interiorLineSpacing)
        + THKBlockQuoteMetrics.secondLevelBottomSpacing
    text.addAttribute(.paragraphStyle, value: bottomStyle, range: lastRange)
}

/// Copy-button size and margin. Block text reserves a right-hand gutter.
enum THKCopyButtonMetrics {
    static let size: CGFloat = 32
    static let margin: CGFloat = 4
    static let topPaddingReserve: CGFloat = margin + size + margin
}

/// Shared outlined checkbox geometry, matching Android rather than platform glyphs.
/// Size follows the body font; strokes use the configured text color.
func thkCheckboxPrefixAttributedString(checked: Bool, font: UIFont, color: UIColor) -> NSAttributedString {
    let side = font.pointSize * 0.85
    let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
        color.setStroke()
        let lineWidth = side / 10
        let box = UIBezierPath(roundedRect: CGRect(x: lineWidth / 2, y: lineWidth / 2, width: side - lineWidth, height: side - lineWidth), cornerRadius: side / 8)
        box.lineWidth = lineWidth
        box.stroke()
        if checked {
            let check = UIBezierPath()
            check.move(to: CGPoint(x: side * 0.22, y: side * 0.51))
            check.addLine(to: CGPoint(x: side * 0.43, y: side * 0.72))
            check.addLine(to: CGPoint(x: side * 0.79, y: side * 0.28))
            check.lineWidth = lineWidth
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        }
    }

    let attachment = NSTextAttachment()
    attachment.image = image
    // Centers the glyph on the text's cap-height rather than its baseline, matching how the
    // bullet/number markers it replaces sit relative to the following text.
    let yOffset = (font.ascender + font.descender - image.size.height) / 2
    attachment.bounds = CGRect(x: 0, y: yOffset, width: image.size.width, height: image.size.height)

    let result = NSMutableAttributedString(attachment: attachment)
    result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
    let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
    result.append(NSAttributedString(string: " ", attributes: [.font: font, .kern: 4 - spaceWidth]))
    return result
}

/// True when a fenced code block's language/info tag names Mermaid (case-insensitive, tolerant
/// of surrounding whitespace) — the one case where a "code block" becomes a `.diagram` segment
/// instead. Shared by both renderer backends so the detection rule can't drift between them.
func thkIsMermaidLanguageTag(_ tag: String?) -> Bool {
    guard let tag else { return false }
    return tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mermaid"
}

/// Horizontal inset reserved on each side of a code block via `NSParagraphStyle`
/// head/tail indent; `THKBackgroundLayoutManager` does not need to know this value since
/// its background rect stays full-width (indentation alone produces the padded look).
enum THKCodeBlockMetrics {
    static let horizontalPadding: CGFloat = 8
    /// Reserved below the block's last line (matches Android's `CodeBlockBackgroundSpan`
    /// ~8dp `verticalPaddingPx`). Applied per-paragraph, not uniformly across the whole
    /// block range — see `applyCodeBlockParagraphStyles` in each renderer, which sets this
    /// only on the first/last line so interior lines don't also pick it up.
    static let verticalPaddingBottom: CGFloat = 8
    /// The button sits beside the first line, so top and bottom padding stay symmetric.
    static let verticalPaddingTop: CGFloat = 8
    static let copyButtonGutter: CGFloat = THKCopyButtonMetrics.margin + THKCopyButtonMetrics.size + THKCopyButtonMetrics.margin
}

// DefaultMarkdownRenderer lives in SPM/SwiftMarkdownRenderer.swift.
// Both source and binary distributions compile this same swift-markdown adapter.
