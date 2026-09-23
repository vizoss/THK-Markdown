package com.thk.mdview

import android.graphics.Color

/**
 * Immutable color/text configuration for [THKMDView]. Assigning a new value to
 * [THKMDView.theme] re-renders the current content with it — callers never need to
 * call `setMarkdown` again just to pick up a theme change.
 */
data class THKMDTheme(
    /** 正文和列表文字颜色，也用于表格正文。 */
    val bodyTextColor: Int,
    /** 标题与表格表头文字颜色。 */
    val headingTextColor: Int,
    /** 链接文字颜色。 */
    val linkColor: Int,
    /** 行内代码、代码块及复制图标颜色。 */
    val codeTextColor: Int,
    /** 行内代码和代码块背景色。 */
    val codeBackgroundColor: Int,
    /** 代码和引用背景圆角半径，单位 dp。 */
    val codeBlockCornerRadiusDp: Float,
    /** 引用竖条及水平分隔线颜色。 */
    val blockQuoteBarColor: Int,
    /** 引用正文颜色，不覆盖链接和代码颜色。 */
    val blockQuoteTextColor: Int,
    /** 最外层引用背景色，内层引用共享背景。 */
    val blockQuoteBackgroundColor: Int,
    /** 表格网格边框颜色。 */
    val tableBorderColor: Int,
    /** 表格表头背景色。 */
    val tableHeaderBackgroundColor: Int,
    /** 正文基准字号，单位 sp；标题使用此字号乘以主题比例。 */
    val bodyFontSizeSp: Float,
    /** 代码字号，单位 sp。 */
    val codeFontSizeSp: Float,
    /** 整个 Markdown 视图背景色；默认透明，透出宿主聊天气泡背景。 */
    val backgroundColor: Int = Color.TRANSPARENT,
    /** 图片加载中或失败时的占位背景色（ARGB）。 */
    val imagePlaceholderColor: Int = 0xFFE5E5EA.toInt(),
    /** H1 标题相对正文字号的倍率。 */
    val heading1Scale: Float = 1.6f,
    /** H2 标题相对正文字号的倍率。 */
    val heading2Scale: Float = 1.4f,
    /** H3 标题相对正文字号的倍率。 */
    val heading3Scale: Float = 1.25f,
    /** H4 标题相对正文字号的倍率。 */
    val heading4Scale: Float = 1.15f,
    /** H5 标题相对正文字号的倍率。 */
    val heading5Scale: Float = 1.05f,
    /** H6 标题相对正文字号的倍率。 */
    val heading6Scale: Float = 1f,
    /** NOTE 提示块标题和竖条颜色；正文/背景继续使用引用主题。 */
    val alertNoteColor: Int = 0xFF0969DA.toInt(),
    /** TIP 提示块标题和竖条颜色。 */
    val alertTipColor: Int = 0xFF1A7F37.toInt(),
    /** IMPORTANT 提示块标题和竖条颜色。 */
    val alertImportantColor: Int = 0xFF8250DF.toInt(),
    /** WARNING 提示块标题和竖条颜色。 */
    val alertWarningColor: Int = 0xFF9A6700.toInt(),
    /** CAUTION 提示块标题和竖条颜色。 */
    val alertCautionColor: Int = 0xFFCF222E.toInt(),
    /** 脚注引用序号相对正文字号的倍率；颜色使用 linkColor，不跳转外部浏览器。 */
    val footnoteScale: Float = 0.75f,
    /** 公式相对正文字号的倍率；颜色使用 bodyTextColor，背景透明。 */
    val mathScale: Float = 1f,
    /** 无序列表圆点直径相对正文字号的倍率，默认 0.20；跟随 sp/系统字体缩放。
     * 仅 Android：iOS 使用正文字体的原生 • 字形。普通列表、引用和提示块共用。 */
    val listBulletScale: Float = 0.20f
) {
    internal fun alertColor(kind: String): Int? = when (kind) {
        "NOTE" -> alertNoteColor
        "TIP" -> alertTipColor
        "IMPORTANT" -> alertImportantColor
        "WARNING" -> alertWarningColor
        "CAUTION" -> alertCautionColor
        else -> null
    }
    /** Mermaid 复用主题：正文控制字号/文字，代码背景控制节点，表格边框控制连线，
     * 引用/表头背景控制次级区域。JSON 序列化保证配置安全传入 WebView。 */
    internal fun mermaidConfiguration(): org.json.JSONObject {
        fun css(color: Int) = "rgba(${Color.red(color)},${Color.green(color)},${Color.blue(color)},${Color.alpha(color) / 255.0})"
        val variables = org.json.JSONObject()
            .put("fontSize", "${bodyFontSizeSp}px").put("textColor", css(bodyTextColor))
            .put("primaryColor", css(codeBackgroundColor)).put("primaryTextColor", css(bodyTextColor))
            .put("primaryBorderColor", css(tableBorderColor)).put("lineColor", css(tableBorderColor))
            .put("secondaryColor", css(blockQuoteBackgroundColor)).put("tertiaryColor", css(tableHeaderBackgroundColor))
            .put("edgeLabelBackground", css(codeBackgroundColor))
        return org.json.JSONObject().put("startOnLoad", false).put("securityLevel", "strict")
            .put("theme", "base").put("themeVariables", variables)
    }

    companion object {
        val Default = THKMDTheme(
            bodyTextColor = 0xFF1C1C1E.toInt(),
            headingTextColor = 0xFF1C1C1E.toInt(),
            linkColor = 0xFF0A84FF.toInt(),
            codeTextColor = 0xFF3A3A3C.toInt(),
            codeBackgroundColor = 0xFFEEEEEE.toInt(),
            codeBlockCornerRadiusDp = 8f,
            blockQuoteBarColor = 0xFFC7C7CC.toInt(),
            blockQuoteTextColor = 0xFF3A3A3C.toInt(),
            blockQuoteBackgroundColor = 0xFFF5F5F6.toInt(),
            tableBorderColor = 0xFFD1D1D6.toInt(),
            tableHeaderBackgroundColor = 0xFFEFEFF4.toInt(),
            bodyFontSizeSp = 15f,
            codeFontSizeSp = 13f
        )
    }
}
