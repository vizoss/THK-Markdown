import UIKit

/// Colors and text sizes used across both `MarkdownRendering` backends and `THKTableView`.
/// Settable on `THKMDView.theme`; changing it re-renders the current content in place.
public struct THKMDTheme {
    public var bodyTextColor: UIColor
    public var headingTextColor: UIColor
    public var linkColor: UIColor
    public var codeTextColor: UIColor
    public var codeBackgroundColor: UIColor
    public var codeBlockCornerRadius: CGFloat
    public var blockQuoteBarColor: UIColor
    public var blockQuoteTextColor: UIColor
    /// Fill behind a block quote, painted as one continuous rounded shape (reuses
    /// `codeBlockCornerRadius` rather than adding a second radius knob). Only the outermost
    /// level of a nested `> > quote` gets this fill — see `blockQuoteDepth` in
    /// SwiftMarkdownRenderer.swift/MaakuMarkdownRenderer.swift.
    public var blockQuoteBackgroundColor: UIColor
    public var tableBorderColor: UIColor
    public var tableHeaderBackgroundColor: UIColor
    public var bodyFontSize: CGFloat
    public var codeFontSize: CGFloat
    /// Background painted behind the whole view; clear by default so a host's chat-bubble
    /// background (e.g. a card view) shows through unless overridden. Matches Android's
    /// `THKMDTheme.backgroundColor` (default `Color.TRANSPARENT`).
    public var backgroundColor: UIColor

    public init(
        bodyTextColor: UIColor,
        headingTextColor: UIColor,
        linkColor: UIColor,
        codeTextColor: UIColor,
        codeBackgroundColor: UIColor,
        codeBlockCornerRadius: CGFloat,
        blockQuoteBarColor: UIColor,
        blockQuoteTextColor: UIColor,
        blockQuoteBackgroundColor: UIColor,
        tableBorderColor: UIColor,
        tableHeaderBackgroundColor: UIColor,
        bodyFontSize: CGFloat,
        codeFontSize: CGFloat,
        backgroundColor: UIColor = .clear
    ) {
        self.bodyTextColor = bodyTextColor
        self.headingTextColor = headingTextColor
        self.linkColor = linkColor
        self.codeTextColor = codeTextColor
        self.codeBackgroundColor = codeBackgroundColor
        self.codeBlockCornerRadius = codeBlockCornerRadius
        self.blockQuoteBarColor = blockQuoteBarColor
        self.blockQuoteTextColor = blockQuoteTextColor
        self.blockQuoteBackgroundColor = blockQuoteBackgroundColor
        self.tableBorderColor = tableBorderColor
        self.tableHeaderBackgroundColor = tableHeaderBackgroundColor
        self.bodyFontSize = bodyFontSize
        self.codeFontSize = codeFontSize
        self.backgroundColor = backgroundColor
    }

    /// A fixed, non-adaptive palette that matches Android's `THKMDTheme.Default`
    /// (android/thkmdview/src/main/java/com/thk/mdview/THKMDTheme.kt) hex-for-hex. This
    /// deliberately trades iOS's automatic dark-mode adaptation (which the previous
    /// dynamic-system-color default had, via `.label`/`.link`/etc.) for exact cross-platform
    /// visual parity at fixed values — Android's theme doesn't adapt to dark mode either, and
    /// the theme is fully pluggable, so a consumer wanting dark-mode-aware colors can supply
    /// their own `THKMDTheme`.
    public static let `default` = THKMDTheme(
        bodyTextColor: UIColor(thkHex: 0x1C1C1E),
        headingTextColor: UIColor(thkHex: 0x1C1C1E),
        linkColor: UIColor(thkHex: 0x0A84FF),
        codeTextColor: UIColor(thkHex: 0x3A3A3C),
        codeBackgroundColor: UIColor(thkHex: 0xEEEEEE),
        codeBlockCornerRadius: 8,
        blockQuoteBarColor: UIColor(thkHex: 0xC7C7CC),
        blockQuoteTextColor: UIColor(thkHex: 0x3A3A3C),
        blockQuoteBackgroundColor: UIColor(thkHex: 0xF5F5F6),
        tableBorderColor: UIColor(thkHex: 0xD1D1D6),
        tableHeaderBackgroundColor: UIColor(thkHex: 0xEFEFF4),
        bodyFontSize: 15,
        codeFontSize: 13
    )
}

// File-private: an implementation detail of `.default` above, not part of the public API.
private extension UIColor {
    convenience init(thkHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
