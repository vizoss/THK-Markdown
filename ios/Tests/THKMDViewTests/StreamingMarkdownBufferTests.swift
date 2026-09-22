import XCTest
@testable import THKMDView

final class StreamingMarkdownBufferTests: XCTestCase {
    private let fixture = """
    # Streaming Fixture

    This has **bold**, _italic_, and `inline code` all mixed with a [link](https://example.com).

    > A block quote
    > spanning two lines.

    - item one
    - item two
    - [x] done item

    ```swift
    func greet() -> String {
        return "hi"
    }
    ```

    | Col A | Col B |
    | --- | --- |
    | 1 | 2 |

    ~~struck~~ text and a closing paragraph.
    """

    // MARK: - Chunk-fuzz: final buffered text must be byte-identical no matter how it's split.

    func testFixedSizeChunksPreserveFinalText() {
        assertChunkingPreservesText(chunker: fixedSizeChunks(of: 7))
    }

    func testOneCharacterAtATimeChunksPreserveFinalText() {
        assertChunkingPreservesText(chunker: fixedSizeChunks(of: 1))
    }

    func testRandomSizedChunksPreserveFinalText() {
        assertChunkingPreservesText(chunker: randomSizeChunks(seed: 42))
        assertChunkingPreservesText(chunker: randomSizeChunks(seed: 1_337))
    }

    // Flattens every segment (text and table alike) into one comparable string. Not meant to
    // be a faithful plain-text rendering, only a deterministic fingerprint of the segments'
    // content, so two renders of the same buffer are equal iff their segment content matches.
    private func plainText(_ segments: [THKRenderSegment]) -> String {
        segments.map { segment -> String in
            switch segment {
            case .text(let attributed, _):
                return attributed.string
            case .table(let model):
                let header = model.headerCells.map(\.string).joined(separator: "|")
                let rows = model.rows.map { $0.map(\.string).joined(separator: "|") }.joined(separator: "\n")
                return "\(header)\n\(rows)"
            case .diagram(let source):
                return source
            }
        }.joined(separator: "\n")
    }

    func testChunkFuzzFinalRenderMatchesSingleShotRender() {
        let renderer = DefaultMarkdownRenderer()
        let expectedPlainText = plainText(renderer.render(fixture))

        let strategies: [[String]] = [
            fixedSizeChunks(of: 7)(fixture),
            fixedSizeChunks(of: 1)(fixture),
            randomSizeChunks(seed: 7)(fixture),
            randomSizeChunks(seed: 99)(fixture)
        ]

        for chunks in strategies {
            let scheduler = FakeScheduler()
            let buffer = StreamingMarkdownBuffer(debounceInterval: 0.032, scheduler: scheduler)
            var lastRenderedPlainText = ""
            buffer.onRender = { text in
                lastRenderedPlainText = self.plainText(renderer.render(text))
            }

            for chunk in chunks {
                buffer.append(chunk)
            }
            scheduler.fireAll()

            XCTAssertEqual(lastRenderedPlainText, expectedPlainText)
        }
    }

    private func assertChunkingPreservesText(chunker: (String) -> [String]) {
        let scheduler = FakeScheduler()
        let buffer = StreamingMarkdownBuffer(debounceInterval: 0.032, scheduler: scheduler)
        for chunk in chunker(fixture) {
            buffer.append(chunk)
        }
        XCTAssertEqual(buffer.text, fixture)
    }

    private func fixedSizeChunks(of size: Int) -> (String) -> [String] {
        { text in
            var chunks: [String] = []
            var remaining = Substring(text)
            while !remaining.isEmpty {
                let end = remaining.index(remaining.startIndex, offsetBy: size, limitedBy: remaining.endIndex) ?? remaining.endIndex
                chunks.append(String(remaining[remaining.startIndex..<end]))
                remaining = remaining[end...]
            }
            return chunks
        }
    }

    private func randomSizeChunks(seed: UInt64) -> (String) -> [String] {
        { text in
            var generator = SeededGenerator(seed: seed)
            var chunks: [String] = []
            var remaining = Substring(text)
            while !remaining.isEmpty {
                let size = Int.random(in: 1...9, using: &generator)
                let end = remaining.index(remaining.startIndex, offsetBy: size, limitedBy: remaining.endIndex) ?? remaining.endIndex
                chunks.append(String(remaining[remaining.startIndex..<end]))
                remaining = remaining[end...]
            }
            return chunks
        }
    }

    // MARK: - Debounce coalescing

    func testRapidAppendsWithinOneWindowCoalesceIntoOneRender() {
        let scheduler = FakeScheduler()
        let buffer = StreamingMarkdownBuffer(debounceInterval: 0.032, scheduler: scheduler)
        var renderCount = 0
        var lastText = ""
        buffer.onRender = { text in
            renderCount += 1
            lastText = text
        }

        for i in 0..<25 {
            buffer.append("chunk\(i) ")
        }

        // 25 appends each cancel the previous pending work and schedule a new one.
        XCTAssertEqual(scheduler.scheduleCallCount, 25)
        XCTAssertEqual(renderCount, 0, "no render should fire before the debounce window elapses")

        scheduler.fireAll()

        XCTAssertEqual(renderCount, 1, "rapid appends inside one debounce window must coalesce into exactly one render")
        XCTAssertEqual(lastText, buffer.text)
    }

    func testSetFullBypassesDebounceAndRendersImmediately() {
        let scheduler = FakeScheduler()
        let buffer = StreamingMarkdownBuffer(scheduler: scheduler)
        var renderedTexts: [String] = []
        buffer.onRender = { renderedTexts.append($0) }

        buffer.setFull("Hello")

        XCTAssertEqual(renderedTexts, ["Hello"])
        XCTAssertEqual(scheduler.scheduleCallCount, 0)
    }

    // MARK: - Reuse safety

    func testResetCancelsPendingRenderSoItNeverOverwritesNewContent() {
        let scheduler = FakeScheduler()
        let buffer = StreamingMarkdownBuffer(scheduler: scheduler)
        var renderedTexts: [String] = []
        buffer.onRender = { renderedTexts.append($0) }

        // Simulate a message mid-stream in a cell that's about to be recycled.
        buffer.append("Streaming into message A")
        XCTAssertEqual(scheduler.scheduleCallCount, 1)

        // The cell gets recycled for a different row.
        buffer.reset()
        XCTAssertEqual(buffer.text, "")

        // The new row's content is set immediately (not a stream chunk).
        buffer.setFull("Message B: a completely different message")

        // The OLD debounced timer, which reset() should have cancelled, finally "fires".
        scheduler.fireAll()

        XCTAssertEqual(renderedTexts, ["Message B: a completely different message"])
    }

    func testResetWithNoPendingWorkIsSafe() {
        let scheduler = FakeScheduler()
        let buffer = StreamingMarkdownBuffer(scheduler: scheduler)
        buffer.reset()
        XCTAssertEqual(buffer.text, "")
        scheduler.fireAll()
    }
}
