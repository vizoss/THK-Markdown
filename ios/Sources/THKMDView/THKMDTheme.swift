import UIKit

/// Colors and text sizes used across the shared `MarkdownRendering` implementation and `THKTableView`.
/// Settable on `THKMDView.theme`; changing it re-renders the current content in place.
public struct THKMDTheme: Equatable {
    /// 脚注引用序号相对正文字号的倍率；颜色使用 linkColor，不跳转外部浏览器。
    public var footnoteScale: CGFloat = 0.75
    /// 公式相对正文字号的倍率；颜色使用 bodyTextColor，背景透明。
    public var mathScale: CGFloat = 1
    /// NOTE 提示块标题和竖条颜色；正文/背景继续使用引用主题。
    public var alertNoteColor: UIColor = UIColor(thkHex: 0x0969DA)
    /// TIP 提示块标题和竖条颜色。
    public var alertTipColor: UIColor = UIColor(thkHex: 0x1A7F37)
    /// IMPORTANT 提示块标题和竖条颜色。
    public var alertImportantColor: UIColor = UIColor(thkHex: 0x8250DF)
    /// WARNING 提示块标题和竖条颜色。
    public var alertWarningColor: UIColor = UIColor(thkHex: 0x9A6700)
    /// CAUTION 提示块标题和竖条颜色。
    public var alertCautionColor: UIColor = UIColor(thkHex: 0xCF222E)

    internal func alertColor(_ kind: String) -> UIColor? {
        switch kind {
        case "NOTE": return alertNoteColor
        case "TIP": return alertTipColor
        case "IMPORTANT": return alertImportantColor
        case "WARNING": return alertWarningColor
        case "CAUTION": return alertCautionColor
        default: return nil
        }
    }
    /// 图片加载中或失败时的占位背景色。
    public var imagePlaceholderColor: UIColor = UIColor(thkHex: 0xE5E5EA)
    /// 复制成功提示文字颜色（iOS 自绘提示）。
    public var copyFeedbackTextColor: UIColor = .white
    /// 复制成功提示背景色（包含透明度）。
    public var copyFeedbackBackgroundColor: UIColor = UIColor.black.withAlphaComponent(0.75)
    /// 复制成功提示字号，单位 pt。
    public var copyFeedbackFontSize: CGFloat = 12
    /// H1 标题相对正文字号的倍率。
    public var heading1Scale: CGFloat = 1.6
    /// H2 标题相对正文字号的倍率。
    public var heading2Scale: CGFloat = 1.4
    /// H3 标题相对正文字号的倍率。
    public var heading3Scale: CGFloat = 1.25
    /// H4 标题相对正文字号的倍率。
    public var heading4Scale: CGFloat = 1.15
    /// H5 标题相对正文字号的倍率。
    public var heading5Scale: CGFloat = 1.05
    /// H6 标题相对正文字号的倍率。
    public var heading6Scale: CGFloat = 1
    /// Mermaid 图形配置：字号取 bodyFontSize，文字取 bodyTextColor，节点底色取
    /// codeBackgroundColor，边框/连线取 tableBorderColor，次级区域取引用/表头背景。
    /// 通过 JSON/base64 传入模板，不拼接未转义的 JavaScript 字符串。
    internal var mermaidConfiguration: [String: Any] {
        func css(_ color: UIColor) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: .current).getRed(&r, green: &g, blue: &b, alpha: &a)
            return "rgba(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)),\(a))"
        }
        return ["startOnLoad": false, "securityLevel": "strict", "theme": "base",
                "themeVariables": ["fontSize": "\(bodyFontSize)px", "textColor": css(bodyTextColor),
                    "primaryColor": css(codeBackgroundColor), "primaryTextColor": css(bodyTextColor),
                    "primaryBorderColor": css(tableBorderColor), "lineColor": css(tableBorderColor),
                    "secondaryColor": css(blockQuoteBackgroundColor), "tertiaryColor": css(tableHeaderBackgroundColor),
                    "edgeLabelBackground": css(codeBackgroundColor)]]
    }
    /// 正文和列表文字颜色，也用于表格正文。
    public var bodyTextColor: UIColor
    /// 标题与表格表头文字颜色。
    public var headingTextColor: UIColor
    /// 链接文字颜色。
    public var linkColor: UIColor
    /// 行内代码、代码块及复制图标颜色。
    public var codeTextColor: UIColor
    /// 行内代码和代码块背景色。
    public var codeBackgroundColor: UIColor
    /// 代码和引用背景圆角半径，单位 pt。
    public var codeBlockCornerRadius: CGFloat
    /// 引用竖条及水平分隔线颜色。
    public var blockQuoteBarColor: UIColor
    /// 引用正文颜色，不覆盖链接和代码颜色。
    public var blockQuoteTextColor: UIColor
    /// Fill behind a block quote, painted as one continuous rounded shape (reuses
    /// `codeBlockCornerRadius` rather than adding a second radius knob). Only the outermost
    /// level of a nested `> > quote` gets this fill — see `blockQuoteDepth` in
    /// SwiftMarkdownRenderer.swift.
    /// 最外层引用背景色，内层引用共享背景。
    public var blockQuoteBackgroundColor: UIColor
    /// 表格网格边框颜色。
    public var tableBorderColor: UIColor
    /// 表格表头背景色。
    public var tableHeaderBackgroundColor: UIColor
    /// 正文基准字号，单位 pt；标题使用此字号乘以主题比例。
    public var bodyFontSize: CGFloat
    /// 代码字号，单位 pt。
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
