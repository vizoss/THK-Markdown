import UIKit

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
/// (dp ≈ pt at baseline scale). `indentPerLevel` is what each renderer's `visitBlockQuote`
/// multiplies by nesting depth for `headIndent`/`firstLineHeadIndent`; it happens to equal the
/// previous single hardcoded `16`, but is now expressed as bar width + the gap specifically
/// between the bar and the text, per level, rather than one opaque constant.
enum THKBlockQuoteMetrics {
    static let barWidth: CGFloat = 4
    static let barToTextGap: CGFloat = 12
    static let indentPerLevel: CGFloat = barWidth + barToTextGap
    /// Extra breathing room between wrapped/multi-paragraph lines *inside* a quote, on top of
    /// (not instead of) the block-level top/bottom padding below.
    static let interiorLineSpacing: CGFloat = 2
    /// Top-of-first-line / bottom-of-last-line padding for the whole (outermost) quote block —
    /// shared with `THKCodeBlockMetrics.verticalPadding` so both "padded block" types read as
    /// one consistent family, matching Android's shared `BLOCK_VERTICAL_PADDING_DP`.
    static let verticalPadding: CGFloat = THKCodeBlockMetrics.verticalPadding
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
    /// Reserved above the block's first line and below its last line (matches Android's
    /// `CodeBlockBackgroundSpan` ~8dp `verticalPaddingPx`). Applied per-paragraph, not
    /// uniformly across the whole block range — see `codeBlockParagraphStyle` in each
    /// renderer, which sets this only on the first/last line so interior lines don't also
    /// pick it up.
    static let verticalPadding: CGFloat = 8
}

// `DefaultMarkdownRenderer` is intentionally NOT defined here: the SPM distribution's
// swift-markdown-backed implementation lives in SPM/SwiftMarkdownRenderer.swift, and the
// CocoaPods distribution's Maaku-backed implementation lives in
// CocoaPods/MaakuMarkdownRenderer.swift. Package.swift excludes CocoaPods/ and the
// podspec excludes SPM/, so exactly one of the two ever compiles into a given build —
// both are free to reuse the type name `DefaultMarkdownRenderer`.
