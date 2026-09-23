import UIKit

/// NSAttributedString has no built-in "background behind this range, painted as a rounded
/// rect / left bar" concept, so inline code, code blocks, and block quotes are tagged with
/// custom attributes (see MarkdownRenderer.swift) and this NSLayoutManager subclass paints
/// them itself in `drawBackground(forGlyphRange:at:)`, which runs before glyph drawing.
final class THKBackgroundLayoutManager: NSLayoutManager {
    var leadingQuotePadding: CGFloat = 0
    var trailingQuotePadding: CGFloat = 0
    var codeBlockBackgroundColor: UIColor = THKMDTheme.default.codeBackgroundColor
    var inlineCodeBackgroundColor: UIColor = THKMDTheme.default.codeBackgroundColor
    var blockQuoteBarColor: UIColor = THKMDTheme.default.blockQuoteBarColor
    var blockQuoteBackgroundColor: UIColor = THKMDTheme.default.blockQuoteBackgroundColor
    var codeBlockCornerRadius: CGFloat = 6
    var thematicBreakColor: UIColor = THKMDTheme.default.blockQuoteBarColor

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        context.saveGState()

        // Parent backgrounds must be painted before child code backgrounds.
        textStorage.enumerateAttribute(.thkBlockQuoteBackground, in: charRange) { value, range, _ in
            guard value != nil else { return }
            drawFullWidthBackground(for: range, color: blockQuoteBackgroundColor, origin: origin, cornerRadius: codeBlockCornerRadius, includesQuotePadding: true)
        }

        textStorage.enumerateAttribute(.thkCodeBlockBackground, in: charRange) { value, range, _ in
            guard value != nil else { return }
            drawFullWidthBackground(for: range, color: codeBlockBackgroundColor, origin: origin, cornerRadius: codeBlockCornerRadius)
        }

        textStorage.enumerateAttribute(.thkInlineCodeBackground, in: charRange) { value, range, _ in
            guard value != nil else { return }
            drawInlineBackground(for: range, color: inlineCodeBackgroundColor, origin: origin, cornerRadius: 3)
        }

        // A depth attribute describes the deepest quote at each character. Collect
        // continuous ranges at every level so the outer bar also spans nested quotes.
        textStorage.enumerateAttribute(.thkCopyableBlockQuote, in: NSRange(location: 0, length: textStorage.length)) { value, quoteRange, _ in
            guard value != nil, NSIntersectionRange(quoteRange, charRange).length > 0 else { return }
            var rangesByDepth: [Int: [NSRange]] = [:]
            textStorage.enumerateAttribute(.thkBlockQuoteBar, in: quoteRange) { value, range, _ in
                guard let depth = value as? Int, depth > 0 else { return }
                for level in 1...depth {
                    var ranges = rangesByDepth[level, default: []]
                    if let last = ranges.last, NSMaxRange(last) == range.location {
                        ranges[ranges.count - 1] = NSUnionRange(last, range)
                    } else {
                        ranges.append(range)
                    }
                    rangesByDepth[level] = ranges
                }
            }
            for depth in rangesByDepth.keys.sorted() {
                for range in rangesByDepth[depth, default: []] {
                    drawBlockQuoteBar(for: range, origin: origin, depth: depth)
                }
            }
        }

        textStorage.enumerateAttribute(.thkThematicBreak, in: charRange) { value, range, _ in
            guard value != nil else { return }
            drawThematicBreak(for: range, origin: origin)
        }

        context.restoreGState()
    }

    // Draws ONE rounded shape spanning every line of the block, rather than a separate
    // rounded rect per line fragment (which produced a stack of independently-pill-shaped
    // lines instead of a single continuous block). `lineFragmentRect` already includes any
    // paragraphSpacingBefore/paragraphSpacing reserved on the first/last line (see
    // codeBlockParagraphStyle in SwiftMarkdownRenderer.swift/MaakuMarkdownRenderer.swift),
    // so unioning the line rects picks up that vertical padding automatically.
    // Shared by drawFullWidthBackground/drawBlockQuoteBar: one rect spanning every line of the
    // range, in this glyph range's own coordinate space (origin already applied), rather than
    // each duplicating the "walk line fragments and union them" loop.
    private func unionOfLineFragmentRects(forGlyphRange glyphRange: NSRange, origin: CGPoint) -> CGRect? {
        var unionRect: CGRect?
        enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            var r = rect
            r.origin.x += origin.x
            r.origin.y += origin.y
            unionRect = unionRect?.union(r) ?? r
        }
        return unionRect
    }

    private func drawFullWidthBackground(for charRange: NSRange, color: UIColor, origin: CGPoint, cornerRadius: CGFloat, includesQuotePadding: Bool = false) {
        guard charRange.length > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard var rect = unionOfLineFragmentRects(forGlyphRange: glyphRange, origin: origin) else { return }
        if includesQuotePadding {
            let indent = textStorage?.attribute(thkQuoteContainerIndentKey, at: charRange.location, effectiveRange: nil) as? CGFloat ?? 0
            rect.origin.x += indent
            rect.size.width = max(0, rect.width - indent)
        }
        if !includesQuotePadding,
           let style = textStorage?.attribute(.paragraphStyle, at: charRange.location, effectiveRange: nil) as? NSParagraphStyle {
            // The background starts at the containing quote/list content edge;
            // the code's own horizontal padding stays inside that background.
            let left = origin.x + max(0, style.headIndent - THKCodeBlockMetrics.horizontalPadding)
            let quoted = textStorage?.attribute(.thkBlockQuoteBackground, at: charRange.location, effectiveRange: nil) != nil
            let right = rect.maxX - (quoted ? THKCodeBlockMetrics.horizontalPadding : 0)
            rect.origin.x = left
            rect.size.width = max(0, right - left)
        }
        // Container-edge paragraph spacing is transferred to textContainerInset by
        // THKMDView. Extend the owning background over that inset. Quoted code
        // must not consume the quote's inset a second time.
        let ownsInset = includesQuotePadding ||
            textStorage?.attribute(.thkBlockQuoteBackground, at: charRange.location, effectiveRange: nil) == nil
        if ownsInset, charRange.location == 0, leadingQuotePadding > 0 {
            rect.origin.y -= leadingQuotePadding
            rect.size.height += leadingQuotePadding
        }
        if ownsInset, let storage = textStorage, NSMaxRange(charRange) == storage.length,
           trailingQuotePadding > 0 {
            rect.size.height += trailingQuotePadding
        }
        color.setFill()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        context.addPath(path.cgPath)
        context.fillPath()
    }

    private func drawInlineBackground(for charRange: NSRange, color: UIColor, origin: CGPoint, cornerRadius: CGFloat) {
        guard charRange.length > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard let container = textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil) else { return }
        color.setFill()
        enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: container
        ) { rect, _ in
            var r = rect
            r.origin.x += origin.x
            r.origin.y += origin.y
            let path = UIBezierPath(roundedRect: r.insetBy(dx: -1, dy: -1), cornerRadius: cornerRadius)
            context.addPath(path.cgPath)
        }
        context.fillPath()
    }

    // `depth` (1 for the outermost quote, 2+ for each nested level — see `.thkBlockQuoteBar` in
    // MarkdownRenderer.swift) offsets the bar rightward by one `indentPerLevel` per extra level,
    // so a nested quote's bar draws as its own parallel stripe instead of at the exact same
    // pixels as its parent's. Drawn as a rounded "pill" — same union-then-round technique as
    // drawFullWidthBackground, just inset from the block's left/top/bottom edges instead of
    // flush against them — so a multi-line bar reads as one continuous shape.
    private func drawBlockQuoteBar(for charRange: NSRange, origin: CGPoint, depth: Int) {
        guard charRange.length > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard var rect = unionOfLineFragmentRects(forGlyphRange: glyphRange, origin: origin) else { return }

        let leftInset = THKBlockQuoteMetrics.barLeftInset
        let verticalInset: CGFloat = depth == 1 ? 11 : 3
        let containerIndent = textStorage?.attribute(thkQuoteContainerIndentKey, at: charRange.location, effectiveRange: nil) as? CGFloat ?? 0
        rect.origin.x += containerIndent + leftInset + CGFloat(depth - 1) * THKBlockQuoteMetrics.indentPerLevel
        rect.size.width = THKBlockQuoteMetrics.barWidth
        rect.origin.y += verticalInset
        rect.size.height -= verticalInset * 2
        if let storage = textStorage {
            // Line fragments include paragraph padding and the extra line spacing.
            // Align all bars to the text baselines instead, excluding both the
            // outer quote's bottom padding and the second-level quote's top gap.
            var textTop = CGFloat.greatestFiniteMagnitude
            var textBottom = -CGFloat.greatestFiniteMagnitude
            storage.enumerateAttribute(.font, in: charRange) { value, range, _ in
                guard let font = value as? UIFont else { return }
                let run = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard run.length > 0 else { return }
                let first = run.location
                let last = NSMaxRange(run) - 1
                let firstBaseline = self.lineFragmentRect(forGlyphAt: first, effectiveRange: nil).minY + self.location(forGlyphAt: first).y
                let lastBaseline = self.lineFragmentRect(forGlyphAt: last, effectiveRange: nil).minY + self.location(forGlyphAt: last).y
                textTop = min(textTop, firstBaseline - font.capHeight)
                textBottom = max(textBottom, lastBaseline - font.descender)
            }
            if textBottom > textTop {
                rect.origin.y = origin.y + textTop
                rect.size.height = textBottom - textTop
                // When the outer quote contains only nested content, its bar must
                // still span the second-level quote's surrounding blank space.
                // Inner bars remain aligned to their own text, including level 3.
                if depth == 1 {
                    let firstDepth = storage.attribute(.thkBlockQuoteBar, at: charRange.location, effectiveRange: nil) as? Int ?? 1
                    let lastDepth = storage.attribute(.thkBlockQuoteBar, at: NSMaxRange(charRange) - 1, effectiveRange: nil) as? Int ?? 1
                    if firstDepth >= 2 {
                        rect.origin.y -= THKBlockQuoteMetrics.secondLevelTopSpacing
                        rect.size.height += THKBlockQuoteMetrics.secondLevelTopSpacing
                    }
                    if lastDepth >= 2 {
                        rect.size.height += THKBlockQuoteMetrics.secondLevelBottomSpacing
                    }
                }
            }
        }
        guard rect.height > 0 else { return }

        blockQuoteBarColor.setFill()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: THKBlockQuoteMetrics.barWidth / 2)
        context.addPath(path.cgPath)
        context.fillPath()
    }

    // Draws a real solid divider line (rather than relying on a run of Unicode box-drawing/
    // horizontal-bar characters, whose glyph side-bearing varies by font and could render as
    // visibly dashed/gapped) - a thin filled rect at the line's vertical center, spanning its
    // full width, so both this and Android's equivalent ThematicBreakSpan render an identical,
    // font-independent line regardless of typeface. See `.thkThematicBreak` in
    // MarkdownRenderer.swift.
    private func drawThematicBreak(for charRange: NSRange, origin: CGPoint) {
        guard charRange.length > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        thematicBreakColor.setFill()
        enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            var lineRect = rect
            lineRect.origin.x += origin.x
            lineRect.origin.y += origin.y
            let thickness: CGFloat = 1.5
            let centerY = lineRect.midY
            context.fill(CGRect(x: lineRect.minX, y: centerY - thickness / 2, width: lineRect.width, height: thickness))
        }
    }
}
