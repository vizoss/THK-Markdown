import UIKit

/// CJK fallback fonts do not reliably provide italic faces. Our TextKit 1 views
/// use glyph skew for these characters while retaining native italics for Latin.
enum THKEmphasisStyling {
    static func applyCJKFallback(to text: NSMutableAttributedString) {
        let source = text.string as NSString
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length),
                                   options: .byComposedCharacterSequences) { substring, range, _, _ in
            guard let substring, substring.unicodeScalars.contains(where: { scalar in
                switch scalar.value {
                case 0x2E80...0xA4CF, 0xAC00...0xD7AF, 0xF900...0xFAFF,
                     0xFE30...0xFE4F, 0xFF00...0xFFEF, 0x20000...0x323AF:
                    return true
                default: return false
                }
            }) else { return }
            // Avoid applying both a font italic face and an additional skew.
            if let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont {
                var traits = font.fontDescriptor.symbolicTraits
                traits.remove(.traitItalic)
                if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                    text.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: range)
                }
            }
            // Assign, rather than accumulate: nested emphasis must not double the slant.
            text.addAttribute(.obliqueness, value: 0.2, range: range)
        }
    }
}
