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
    public var tableBorderColor: UIColor
    public var tableHeaderBackgroundColor: UIColor
    public var bodyFontSize: CGFloat
    public var codeFontSize: CGFloat

    public init(
        bodyTextColor: UIColor,
        headingTextColor: UIColor,
        linkColor: UIColor,
        codeTextColor: UIColor,
        codeBackgroundColor: UIColor,
        codeBlockCornerRadius: CGFloat,
        blockQuoteBarColor: UIColor,
        blockQuoteTextColor: UIColor,
        tableBorderColor: UIColor,
        tableHeaderBackgroundColor: UIColor,
        bodyFontSize: CGFloat,
        codeFontSize: CGFloat
    ) {
        self.bodyTextColor = bodyTextColor
        self.headingTextColor = headingTextColor
        self.linkColor = linkColor
        self.codeTextColor = codeTextColor
        self.codeBackgroundColor = codeBackgroundColor
        self.codeBlockCornerRadius = codeBlockCornerRadius
        self.blockQuoteBarColor = blockQuoteBarColor
        self.blockQuoteTextColor = blockQuoteTextColor
        self.tableBorderColor = tableBorderColor
        self.tableHeaderBackgroundColor = tableHeaderBackgroundColor
        self.bodyFontSize = bodyFontSize
        self.codeFontSize = codeFontSize
    }

    /// Matches the v0 look: system label/link colors, `secondarySystemBackground` for code,
    /// `systemGray3` for the block quote bar.
    public static let `default` = THKMDTheme(
        bodyTextColor: .label,
        headingTextColor: .label,
        linkColor: .link,
        codeTextColor: .label,
        codeBackgroundColor: .secondarySystemBackground,
        codeBlockCornerRadius: 8,
        blockQuoteBarColor: .systemGray3,
        blockQuoteTextColor: .secondaryLabel,
        tableBorderColor: .separator,
        tableHeaderBackgroundColor: .secondarySystemBackground,
        bodyFontSize: 17,
        codeFontSize: 15
    )
}
