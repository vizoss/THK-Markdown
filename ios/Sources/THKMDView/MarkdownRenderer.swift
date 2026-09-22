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
/// it needs a real, independently hit-testable, horizontally scrollable view.
public enum THKRenderSegment {
    case text(NSAttributedString)
    case table(THKTableModel)
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
}

/// Horizontal inset reserved on each side of a code block via `NSParagraphStyle`
/// head/tail indent; `THKBackgroundLayoutManager` does not need to know this value since
/// its background rect stays full-width (indentation alone produces the padded look).
enum THKCodeBlockMetrics {
    static let horizontalPadding: CGFloat = 8
}

// `DefaultMarkdownRenderer` is intentionally NOT defined here: the SPM distribution's
// swift-markdown-backed implementation lives in SPM/SwiftMarkdownRenderer.swift, and the
// CocoaPods distribution's Maaku-backed implementation lives in
// CocoaPods/MaakuMarkdownRenderer.swift. Package.swift excludes CocoaPods/ and the
// podspec excludes SPM/, so exactly one of the two ever compiles into a given build —
// both are free to reuse the type name `DefaultMarkdownRenderer`.
