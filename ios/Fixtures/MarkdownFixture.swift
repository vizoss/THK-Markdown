import Foundation

public struct MarkdownFixture: Decodable {
    public let id: String
    public let title: String
    public let category: String
    public let platforms: [String]
    public let markdown: String
    public let chunks: [String]
    public let history: [String]
    public let checkpoints: [Checkpoint]
    public let expected: Expectations

    public struct Checkpoint: Decodable {
        public let afterChunk: Int
        public let tableCount: Int
        public let diagramCount: Int
        public let textContains: [String]
    }

    public struct Expectations: Decodable {
        public let mathCount: Int?
        public let textContains: [String]
        public let copyTexts: [String]
        public let tableCount: Int
        public let diagramCount: Int
        public let notes: [String]
    }

    public var summary: String {
        ([id + " · " + title] + expected.notes +
         ["表格：\(expected.tableCount)，图表：\(expected.diagramCount)",
          "预期复制内容：\n" + (expected.copyTexts.isEmpty ? "按块检查，无固定断言" : expected.copyTexts.joined(separator: "\n——\n"))]).joined(separator: "\n")
    }

    public static func load(from url: URL) throws -> [MarkdownFixture] {
        struct Catalog: Decodable { let schemaVersion: Int; let cases: [MarkdownFixture] }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1,
              Set(catalog.cases.map(\.id)).count == catalog.cases.count,
              !catalog.cases.isEmpty,
              catalog.cases.allSatisfy({ fixture in
                  !fixture.chunks.isEmpty && fixture.chunks.joined() == fixture.markdown &&
                  fixture.checkpoints.allSatisfy { (1...fixture.chunks.count).contains($0.afterChunk) }
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return catalog.cases
    }

    /// Load one suite; keep P0 as the default for existing regression tests.
    public static func load(suite: String = "p0") throws -> [MarkdownFixture] {
        guard ["p0", "p1", "p2", "p3"].contains(suite) else { throw CocoaError(.fileNoSuchFile) }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: FixtureBundleAnchor.self)
        #endif
        guard let url = bundle.url(forResource: suite, withExtension: "json", subdirectory: "data")
                ?? bundle.url(forResource: suite, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: url)
    }

    public static func loadAll() throws -> [MarkdownFixture] {
        try ["p0", "p1", "p2", "p3"].flatMap { try load(suite: $0) }
    }
}

private final class FixtureBundleAnchor: NSObject {}
