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

    public static func load() throws -> [MarkdownFixture] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: FixtureBundleAnchor.self)
        #endif
        guard let url = bundle.url(forResource: "p0", withExtension: "json", subdirectory: "data")
                ?? bundle.url(forResource: "p0", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: url)
    }
}

private final class FixtureBundleAnchor: NSObject {}
