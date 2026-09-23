import Foundation

/// Small, deliberately bounded syntax layer shared in behavior with Android.
/// Code fences, indented code, code spans, escaped punctuation and link destinations
/// are opaque. Footnote definitions are document-level; nested definitions stay literal.
enum THKMarkdownExtensions {
    static func prepare(_ source: String) -> String {
        let protected = protectCode(source.replacingOccurrences(of: "\r\n", with: "\n"))
        let lines = protected.0.components(separatedBy: "\n")
        var definitions: [String: String] = [:]
        var body: [String] = []
        var fence: (Character, Int)?
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if updateFence(line, fence: &fence) || line.hasPrefix("    ") || line.hasPrefix("\t") || captures("^ {0,3}\\[(?!\\^)[^\\]]+\\]:", line) != nil {
                body.append(line); i += 1; continue
            }
            if let match = captures("^ {0,3}\\[\\^([^\\]\\s]+)\\]:[ \\t]*(.*)$", line) {
                var definition = match[2]
                i += 1
                while i < lines.count {
                    if lines[i].hasPrefix("    ") {
                        definition += "\n" + lines[i].dropFirst(4); i += 1
                    } else if lines[i].isEmpty && i + 1 < lines.count && lines[i + 1].hasPrefix("    ") {
                        definition += "\n"; i += 1
                    } else { break }
                }
                if definitions[match[1]] == nil { definitions[match[1]] = definition }
                body.append("")
            } else { body.append(line); i += 1 }
        }
        var order: [String] = []
        var output: [String] = []
        fence = nil
        i = 0
        while i < body.count {
            let line = body[i]
            if updateFence(line, fence: &fence) || line.hasPrefix("    ") || line.hasPrefix("\t") || captures("^ {0,3}\\[(?!\\^)[^\\]]+\\]:", line) != nil {
                output.append(line); i += 1; continue
            }
            // A display delimiter must occupy its own top-level line. Incomplete
            // blocks stay literal throughout streaming, never become a phantom image.
            let trim = line.trimmingCharacters(in: .whitespaces)
            if trim == "$$" || trim == "\\[" {
                let close = trim == "$$" ? "$$" : "\\]"
                if let end = ((i + 1)..<body.count).first(where: { body[$0].trimmingCharacters(in: .whitespaces) == close }) {
                    let tex = body[(i + 1)..<end].joined(separator: "\n")
                    output.append("\n" + mathImage(tex, display: true, literals: protected.1) + "\n")
                    i = end + 1; continue
                }
                output.append(contentsOf: body[i...]); break
            }
            output.append(inline(line, definitions: definitions, order: &order, literals: protected.1))
            i += 1
        }
        if !order.isEmpty {
            output.append("\n---\n")
            for (index, label) in order.enumerated() {
                // Definitions may contain inline formatting but do not recursively
                // allocate footnotes; cycles and unused definitions cannot grow output.
                var ignored: [String] = []
                let value = inline(definitions[label] ?? "", definitions: [:], order: &ignored, literals: protected.1)
                output.append("\(index + 1). " + value.replacingOccurrences(of: "\n", with: "\n    "))
            }
        }
        var result = output.joined(separator: "\n")
        for (token, literal) in protected.1 { result = result.replacingOccurrences(of: token, with: literal) }
        return result
    }

    /// Opaque tokens also protect multiline code spans, before definition discovery.
    private static func protectCode(_ source: String) -> (String, [(String, String)]) {
        var fence: (Character, Int)?
        var pending: [String] = [], parts: [String] = [], literals: [(String, String)] = []
        func flush() {
            guard !pending.isEmpty else { return }
            let value = protectSpans(pending.joined(separator: "\n"))
            parts.append(value.0); literals += value.1; pending = []
        }
        for line in source.components(separatedBy: "\n") {
            if updateFence(line, fence: &fence) { flush(); parts.append(line) }
            else { pending.append(line) }
        }
        flush()
        return (parts.joined(separator: "\n"), literals)
    }

    private static func protectSpans(_ source: String) -> (String, [(String, String)]) {
        let chars = Array(source)
        let nonce = "THKOPAQUE" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var saved: [(String, String)] = [], output = "", i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count { output += String(chars[i...i + 1]); i += 2; continue }
            if chars[i] == "`" {
                var end = i + 1
                while end < chars.count && chars[end] == "`" { end += 1 }
                if let close = lineRange(chars, from: end, delimiter: String(chars[i..<end])) {
                    let literal = String(chars[i..<close])
                    if end - i >= 3 || !literal.contains("\n\n") {
                        let token = nonce + "N\(saved.count)END"
                        saved.append((token, literal)); output += token; i = close; continue
                    }
                }
                output += String(chars[i..<end]); i = end; continue
            }
            output.append(chars[i]); i += 1
        }
        return (output, saved)
    }

    private static func updateFence(_ line: String, fence: inout (Character, Int)?) -> Bool {
        // Strip quote/list prefixes only for detecting protected fenced code.
        let probe = line.replacingOccurrences(of: "^(?: {0,3}>[ ]?)*", with: "", options: .regularExpression)
        if let active = fence {
            if let m = captures("^ {0,3}(`{3,}|~{3,})[ \\t]*$", probe), m[1].first == active.0, m[1].count >= active.1 { fence = nil }
            return true
        }
        if let m = captures("^ {0,3}(`{3,}|~{3,})(.*)$", probe), let character = m[1].first {
            fence = (character, m[1].count); return true
        }
        return false
    }

    private static func inline(_ line: String, definitions: [String: String], order: inout [String], literals: [(String, String)] = []) -> String {
        let chars = Array(line)
        var out = "", i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "`" {
                var end = i + 1
                while end < chars.count && chars[end] == "`" { end += 1 }
                let delimiter = String(chars[i..<end])
                if let close = lineRange(chars, from: end, delimiter: delimiter) {
                    // Closing run must have exactly the same length.
                    out += String(chars[i..<close]); i = close; continue
                }
                out += delimiter; i = end; continue
            }
            if ch == "\\" {
                if i + 1 < chars.count && chars[i + 1] == "(", let end = find(chars, from: i + 2, delimiter: ["\\", ")"]) {
                    out += mathImage(String(chars[(i + 2)..<end]), display: false, literals: literals); i = end + 2; continue
                }
                let end = min(i + 2, chars.count)
                out += String(chars[i..<end]); i = end; continue
            }
            // Raw HTML/autolinks and Markdown link destinations are never interpreted.
            if ch == "<", let end = chars[(i + 1)...].firstIndex(of: ">") {
                out += String(chars[i...end]); i = end + 1; continue
            }
            if ch == "]", i + 1 < chars.count, chars[i + 1] == "(" {
                var end = i + 2, depth = 1
                while end < chars.count && depth > 0 {
                    if chars[end] == "\\" { end = min(end + 2, chars.count); continue }
                    if chars[end] == "(" { depth += 1 }
                    if chars[end] == ")" { depth -= 1 }
                    end += 1
                }
                out += String(chars[i..<end]); i = end; continue
            }
            if ch == "[", i + 2 < chars.count, chars[i + 1] == "^", let end = chars[(i + 2)...].firstIndex(of: "]") {
                let label = String(chars[(i + 2)..<end])
                if definitions[label] != nil {
                    if !order.contains(label) { order.append(label) }
                    let number = (order.firstIndex(of: label) ?? 0) + 1
                    out += "[\(number)](thk-footnote://reference)"; i = end + 1; continue
                }
            }
            if ch == "$", i + 1 < chars.count, !chars[i + 1].isWhitespace {
                let count = chars[i + 1] == "$" ? 2 : 1
                let delimiter = Array(repeating: Character("$"), count: count)
                if let end = find(chars, from: i + count, delimiter: delimiter), end > i + count,
                   !chars[end - 1].isWhitespace,
                   !(end + count < chars.count && chars[end + count].isNumber) {
                    out += mathImage(String(chars[(i + count)..<end]), display: count == 2, literals: literals)
                    i = end + count; continue
                }
            }
            out.append(ch); i += 1
        }
        return out
    }

    private static func find(_ chars: [Character], from start: Int, delimiter: [Character]) -> Int? {
        var i = start
        while i + delimiter.count <= chars.count {
            if chars[i] == "\\" && delimiter.first != "\\" { i += 2; continue }
            if Array(chars[i..<(i + delimiter.count)]) == delimiter { return i }
            i += 1
        }
        return nil
    }
    private static func lineRange(_ chars: [Character], from start: Int, delimiter: String) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] != "`" { i += 1; continue }
            let begin = i
            while i < chars.count && chars[i] == "`" { i += 1 }
            if i - begin == delimiter.count { return i }
        }
        return nil
    }
    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { (text as NSString).substring(with: match.range(at: $0)) }
    }
    private static func mathImage(_ input: String, display: Bool, literals: [(String, String)] = []) -> String {
        var tex = input
        for (token, literal) in literals { tex = tex.replacingOccurrences(of: token, with: literal) }
        guard !tex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, tex.utf8.count <= 8192 else { return tex }
        let encoded = Data(tex.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "![formula](thk-math://\(display ? "display" : "inline")/\(encoded))"
    }
}
