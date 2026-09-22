import UIKit

/// NSAttributedString has no built-in "background behind this range, painted as a rounded
/// rect / left bar" concept, so inline code, code blocks, and block quotes are tagged with
/// custom attributes (see MarkdownRenderer.swift) and this NSLayoutManager subclass paints
/// them itself in `drawBackground(forGlyphRange:at:)`, which runs before glyph drawing.
final class THKBackgroundLayoutManager: NSLayoutManager {
    var codeBlockBackgroundColor: UIColor = UIColor.secondarySystemBackground
    var inlineCodeBackgroundColor: UIColor = UIColor.secondarySystemBackground
    var blockQuoteBarColor: UIColor = UIColor.systemGray3

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        context.saveGState()

        textStorage.enumerateAttribute(.thkCodeBlockBackground, in: charRange) { value, range, _ in
            guard value != nil else { return }
            drawFullWidthBackground(for: range, color: codeBlockBackgroundColor, origin: origin, cornerRadius: 6)
        }

        textStorage.enumerateAttribute(.thkInlineCodeBackground, in: charRange) { value, range, _ in
            guard value != nil else { return }
            drawInlineBackground(for: range, color: inlineCodeBackgroundColor, origin: origin, cornerRadius: 3)
        }

        textStorage.enumerateAttribute(.thkBlockQuoteBar, in: charRange) { value, range, _ in
            guard value != nil else { return }
            drawBlockQuoteBar(for: range, origin: origin)
        }

        context.restoreGState()
    }

    private func drawFullWidthBackground(for charRange: NSRange, color: UIColor, origin: CGPoint, cornerRadius: CGFloat) {
        guard charRange.length > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        color.setFill()
        enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            var r = rect
            r.origin.x += origin.x
            r.origin.y += origin.y
            let path = UIBezierPath(roundedRect: r.insetBy(dx: 0, dy: -1), cornerRadius: cornerRadius)
            context.addPath(path.cgPath)
        }
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

    private func drawBlockQuoteBar(for charRange: NSRange, origin: CGPoint) {
        guard charRange.length > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        blockQuoteBarColor.setFill()
        enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            var barRect = rect
            barRect.origin.x += origin.x
            barRect.origin.y += origin.y
            barRect.size.width = 3
            context.fill(barRect)
        }
    }
}
