// Run together with THKMarkdownExtensions.swift using the Swift interpreter.
// Foundation only: does not build, launch or drive either example application.
import Foundation

let fixtureDirectory = URL(fileURLWithPath: "ios/Fixtures/data")
var checked = 0
for suite in ["p0", "p1", "p2", "p3"] {
    let data = try Data(contentsOf: fixtureDirectory.appendingPathComponent(suite + ".json"))
    let catalog = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let cases = catalog["cases"] as! [[String: Any]]
    for fixture in cases {
        let source = fixture["markdown"] as! String
        let chunks = fixture["chunks"] as! [String]
        precondition(chunks.joined() == source, "chunk loss: \(fixture["id"]!)")
        var partial = ""
        for chunk in chunks { partial += chunk; _ = THKMarkdownExtensions.prepare(partial) }
        let prepared = THKMarkdownExtensions.prepare(source)
        if suite != "p3" { precondition(prepared == source.replacingOccurrences(of: "\r\n", with: "\n"), "legacy changed: \(fixture["id"]!)") }
        if let expected = fixture["expected"] as? [String: Any], let count = expected["mathCount"] as? Int {
            precondition(prepared.components(separatedBy: "thk-math://").count - 1 == count, "math count: \(fixture["id"]!)")
        }
        checked += 1
    }
}
for literal in ["`$x$ [^a]`", "```text\n$x$\n[^a]: not a note\n```", "    $x$", "[url](https://example.com/$x$)", "\\$x\\$"] {
    precondition(THKMarkdownExtensions.prepare(literal) == literal)
}
for literal in ["`line\n$x$ [^a]\nend`", "[ref]: https://example.com/$x$", "~~~\n` $x$ `\n~~~", "```\n$x$\n````"] {
    precondition(THKMarkdownExtensions.prepare(literal) == literal, "protected context changed")
}
let notes = THKMarkdownExtensions.prepare("先[^b] 后[^a] 再[^b]。\n\n[^a]: A\n[^b]: B\n[^unused]: UNUSED")
precondition(notes.contains("1. B\n2. A") && !notes.contains("UNUSED"))
print("P3 source checks passed; \(checked) catalogs, every streaming chunk; no app launched.")
