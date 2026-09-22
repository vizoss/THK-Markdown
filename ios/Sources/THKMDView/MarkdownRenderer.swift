import UIKit

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

// `DefaultMarkdownRenderer` is intentionally NOT defined here: the SPM distribution's
// swift-markdown-backed implementation lives in SPM/SwiftMarkdownRenderer.swift, and the
// CocoaPods distribution's Maaku-backed implementation lives in
// CocoaPods/MaakuMarkdownRenderer.swift. Package.swift excludes CocoaPods/ and the
// podspec excludes SPM/, so exactly one of the two ever compiles into a given build —
// both are free to reuse the type name `DefaultMarkdownRenderer`.
