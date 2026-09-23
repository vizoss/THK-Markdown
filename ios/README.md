# THKMDView (iOS)

P3 提示块、基础脚注与离线公式已接入，36 个共享用例及主题配置见 [P3 文档](../docs/P3.zh-CN.md)。SPM/XCFramework 均需携带 MathJax JS、HTML 模板和许可证；示例不进入二进制。尚待双端编译、渲染和视觉验收。

A UIKit Swift Package that renders streaming Markdown inside a chat bubble — the kind of
view you drop into a `UITableView`/`UICollectionView` cell to show an LLM reply as it
arrives over SSE. See [`../docs/RESEARCH.md`](../docs/RESEARCH.md) for the full
architecture rationale.

`THKMDView` ships via two independent distributions that share every file except the
Markdown parser itself — see "Two distributions, one parser swapped" below.

## Requirements

The example now uses the shared 18-case P0 catalog through the `MarkdownFixtures` product, with case selection, full text, play, pause and single-step controls. See [P0 acceptance guide](../docs/P0.zh-CN.md) for the current workflow; this replaces the previous rotating mock replies.

- Xcode 26+ / Swift 6.2+ for source builds (required by the pinned parser manifest).
- iOS 13+
- [swift-markdown](https://github.com/swiftlang/swift-markdown), pinned to the same revision for source and binary builds. The current pin requires Swift 6.2+ (Xcode 26+).
- CocoaPods distributes a precompiled XCFramework using this same parser; see [binary packaging](Binary/README.md).

## Architecture in one paragraph

`THKMDView` is a `UIView` owning a vertical `UIStackView` of **segments** (see
`docs/RESEARCH.md` §9). Markdown text is parsed by `swift-markdown` into an AST, then walked to produce an ordered `[THKRenderSegment]`: as many
consecutive non-table top-level blocks as possible (paragraphs, headings, lists, block
quotes, code blocks, thematic breaks) merge into one `.text` segment — a single
non-scrolling, non-editable `UITextView` with one `NSAttributedString` — the same "one
attributed string, custom spans for block constructs" model as v0 (bold/italic become
font traits, links become `.link` attributes, lists become paragraph-style indent + a
literal marker glyph; inline code background, code block background, and block quote bar
have no built-in `NSAttributedString` representation, so they're tagged with custom
attribute keys and painted by `THKBackgroundLayoutManager`, a custom `NSLayoutManager`
subclass overriding `drawBackground(forGlyphRange:at:)`). Each GFM `Table` block instead
becomes its own `.table` segment — a `THKTableView`, a real column-aligned, horizontally
scrollable grid, since a table needs independent touch handling a text view's custom
spans can't provide. Images stay inline in the text flow as a custom `NSTextAttachment`
(`THKAsyncImageTextAttachment`) that starts as a placeholder and swaps in the real bitmap
once `THKImageLoading` resolves it, without re-laying-out the surrounding text. Colors and
sizes for all of this come from a `THKMDTheme` value threaded into the renderer and into
`THKBackgroundLayoutManager`/`THKTableView`. This mirrors Markwon's approach on Android for
the common (no-table) case: one text view, one attributed string, custom spans/drawing for
block constructs — with a composite-view escape hatch for tables and images, per §9.

## Two distributions, one parser

SPM compiles source; CocoaPods downloads a precompiled XCFramework. Both use
`Sources/THKMDView/SPM/SwiftMarkdownRenderer.swift`. Maaku and its adapter are removed.
The binary framework statically links parser dependencies and does not expose their
modules to consuming applications. See [packaging and migration](Binary/README.md).

### Nested block quotes, task-list checkboxes, and quote spacing

A nested `> > quote`'s bar is drawn offset to the right by `(depth - 1) *
THKBlockQuoteMetrics.indentPerLevel` (`THKBackgroundLayoutManager.drawBlockQuoteBar`), so
each nesting level reads as its own parallel rounded-pill stripe instead of drawing
underneath/identical-to its parent's bar at the same x-position — matching Android's
`ThemedQuoteSpan` stacking (there it falls out of `LeadingMarginSpan` margin accumulation;
here it's applied explicitly, since iOS paints bars at the layout-manager level, not a
per-line margin level). A block quote's own children (a wrapped paragraph, a following
paragraph, a nested quote) are joined with a single `"\n"`
(`joinBlocksTightly`/`visitBlockQuote`), not a blank `"\n\n"` paragraph — otherwise a
paragraph/nested-quote boundary would pick up a whole extra blank line on top of
`THKBlockQuoteMetrics.interiorLineSpacing`, reading as a noticeably bigger gap than an
ordinary wrapped line, unlike Android's uniform flat +2pt rhythm. Task-list checkboxes are
an `NSTextAttachment`-wrapped SF Symbol image (`checkmark.square.fill`/`square`, same
family so both share an identical bounding box) rather than literal
`\u{2611}`/`\u{2610}` ballot-box characters, which don't reliably render at matching
visual weight across fonts.

## Building the package

```sh
cd ios
xcodebuild build -scheme THKMDView -destination 'generic/platform=iOS Simulator'
```

The first build resolves the `swift-markdown` SPM dependency (network required); after
that it's cached. `swift build`/`swift test` will **not** work here — this package links
UIKit, which isn't available to a plain macOS SPM toolchain run; you must build/test
against an iOS Simulator destination via `xcodebuild`, as below.

## Running tests

```sh
cd ios
xcrun simctl list devices available   # find a simulator name/id on your machine
xcodebuild test -project Example/Example.xcodeproj -scheme Example -destination 'platform=iOS Simulator,name=iPhone 17'
```

If you have more than one simulator with the same name (e.g. two "iPhone 17 Pro"
entries from different Xcode versions), disambiguate with `id=<UDID>` instead of `name=`:

```sh
xcodebuild test -project Example/Example.xcodeproj -scheme Example -destination 'platform=iOS Simulator,id=<UDID>'
```

The Example scheme includes the SDK and shared P0 tests. Regenerate the project with
`xcodegen generate --spec Example/project.yml` after changing test target configuration.
See [P0 acceptance](../docs/P0-acceptance-2026-09-23.md) for current results and scope.
The original test groups include:

- **`Tests/THKMDViewTests/RenderTests.swift`** — feeds Markdown fixtures through
  `DefaultMarkdownRenderer` and asserts, per segment, plain-text extraction plus the
  presence of the right attribute at the right range: bold/italic font traits (including
  combined `***bold italic***`), inline code (monospace font +
  `.thkInlineCodeBackground`), all six heading levels (bold, strictly decreasing size),
  a code block's and an outermost block quote's `THKCopyableBlock` entry (and that a
  nested, non-outermost quote does not produce one), and a ` ```mermaid ` fenced block
  producing a `.diagram` segment carrying the right source string instead of a normal
  code-block text segment,
  a link's `.link` URL (inline, autolink, and reference-style), a block quote's
  `.thkBlockQuoteBar` + indent (including nesting two levels deep), a code block's
  monospace font + `.thkCodeBlockBackground` + left/right padding (fenced with/without a
  language tag, and indented), strikethrough, ordered/unordered/task lists (including a
  non-1 start index and nesting), escaped characters, raw HTML rendering as inert literal
  text, a real `THKTableModel` table segment (including column alignment and inline
  Markdown inside a cell), an image becoming a `THKAsyncImageTextAttachment` with its alt
  text as the accessibility label, and theme colors/sizes flowing through to body/heading/
  code text. Also covers two "mid-arrival" cases directly (an unterminated code fence, an
  unterminated `**`) to confirm they don't crash and degrade sensibly.
- **`Tests/THKMDViewTests/StreamingMarkdownBufferTests.swift`** — the streaming/chunk-fuzz
  and debounce tests, all driven by `FakeScheduler` (in
  `Tests/THKMDViewTests/FakeScheduler.swift`), a controllable stand-in for
  `DispatchQueueScheduler` so nothing here sleeps or waits on real timers:
  - Splits a multi-construct fixture (headings, bold/italic, inline code, a link, a
    block quote, lists, a code block, a table, strikethrough) at fixed-size, one-char,
    and seeded-random chunk boundaries (`SeededGenerator`, a small reproducible
    SplitMix64 PRNG), feeds each through `StreamingMarkdownBuffer.append`, and asserts
    the reassembled buffer text — and the final rendered plain text — exactly matches a
    single-shot render of the whole fixture.
  - Asserts 25 rapid `append` calls inside one debounce window schedule 25 work items
    (each cancelling the last) but produce exactly **one** render.
  - Asserts `reset()` cancels pending work so a stale debounced render can never overwrite
    content set after it (the direct analog of `prepareForReuse` → rebind).
- **`Tests/THKMDViewTests/THKMDViewTests.swift`** — the same reuse-safety guarantee
  exercised through the public `THKMDView` API with a spy `MarkdownRendering` and a real
  (short) debounce interval, plus `onLinkTap` interception behavior (including the
  "no handler installed → default to opening" case).

## CocoaPods

CocoaPods now consumes the precompiled XCFramework. The old source-pod/Maaku route
is retired. See [binary packaging, local integration and release steps](Binary/README.md).
No binary asset has been published by this migration; remote installation requires
publishing the matching versioned ZIP first.

## Running the Example app

The example is a small UIKit app (`Example/`) — a `UITableViewController` whose cells
each simulate an SSE stream (random 2–6 character chunks, ~30ms apart, via a `Task`) into
a `THKMDView`. Sending a message cycles round-robin through a pool of six reply templates
in `Example/Sources/MockAssistantReply.swift`, each exercising a different construct
cluster: headings/emphasis/links/quotes, code blocks + task lists, nested/ordered lists,
a real table (mixed column alignment) + a cached image
(`https://picsum.photos/seed/thkmdview/480/270`), inert raw HTML, an "everything"
showcase, and a live-rendered Mermaid flowchart. The nav bar's **Theme** button presents a
modal settings sheet (`Example/Sources/ThemeSettingsViewController.swift`) with a live
control for core `THKMDTheme` properties — a `UIColorWell` per color, a `UISlider` per size
— plus two quick-select preset buttons (`.default` and a custom "Vibrant" theme, matching
Android's `ALT_THEME` hex-for-hex) that populate every control at once. Every control
change rebuilds a full `THKMDTheme` from all current control values and pushes it onto
`THKMDView.theme` on every currently visible bubble, without calling `setMarkdown` again,
to prove theming re-renders in place. The sheet uses `UISheetPresentationController`
(`.medium()`/`.large()` detents) and `UIColorWell`, so the Example app's own deployment
target is iOS 15 — higher than the SDK's own iOS 13 minimum, which is fine since the
Example app is a demo, not part of the shipped package.

See the root [theme configuration reference](../README.md#theme-configuration) for
all properties, units, and examples. The sample sheet does not expose every new field;
heading scales, image placeholder color, and copy feedback styling are configurable
through the API.

It's generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from
`Example/project.yml`, and both `project.yml` and the generated `Example.xcodeproj` are
committed, so you can open `Example/Example.xcodeproj` directly in Xcode without
installing XcodeGen. If you change `project.yml`, regenerate with:

```sh
cd ios/Example
xcodegen generate
```

To build from the command line:

```sh
cd ios/Example
xcodebuild build -project Example.xcodeproj -scheme Example -destination 'generic/platform=iOS Simulator'
```

To run it: open `Example/Example.xcodeproj` in Xcode, pick any iOS Simulator, and hit Run
— or install/launch it manually:

```sh
xcrun simctl boot "iPhone 17 Pro"   # skip if a simulator is already booted
xcodebuild build -project Example.xcodeproj -scheme Example -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -iname "Example.app" -path "*iphonesimulator*" | head -1)
xcrun simctl install booted "$APP_PATH"
xcrun simctl launch booted com.thk.mdview.example
```

### `MessageCell.prepareForReuse` — the reuse-safety reference

`Example/Sources/MessageCell.swift` is the reference implementation of correct cell
reuse:

```swift
override func prepareForReuse() {
    super.prepareForReuse()
    streamTask?.cancel()
    streamTask = nil
    markdownView.reset()
}
```

Cancel whatever is feeding chunks into the view *and* call `reset()` — in that order —
before the cell is rebound to a different row. `reset()` clears the internal buffer and
cancels any pending debounced render, so a render that was scheduled for the
recycled-away message can never land on the cell after it starts showing a new one. This
exact scenario (append a chunk → reset mid-flight → set new content → let the stale timer
try to fire) is what
`StreamingMarkdownBufferTests.testResetCancelsPendingRenderSoItNeverOverwritesNewContent`
and `THKMDViewTests.testReuseSafetyAcrossCellRebind` assert.

One thing the example app has to do that isn't part of the SDK itself:
`UITableView.automaticDimension` only re-measures a row's height during its own layout
passes — it does not observe a child view's `invalidateIntrinsicContentSize()` while a
cell is on screen. So while a row is actively streaming, `MessageListViewController`
nudges the table with a periodic `tableView.beginUpdates(); tableView.endUpdates()` (see
`startHeightRefreshTimer()`). If you integrate `THKMDView` into your own streaming list,
you'll want an equivalent nudge — a batch update on each debounced render, throttled to
match your own render cadence, or driven by whatever "content changed" signal your chat
layer already has.

## Public API

```swift
public final class THKMDView: UIView {
    public var streamingDebounceInterval: TimeInterval = 0.032
    public var onLinkTap: ((URL) -> Bool)?
    public var onImageTap: ((URL) -> Bool)?
    public var renderer: MarkdownRendering = DefaultMarkdownRenderer()
    public var imageLoader: THKImageLoading = DefaultTHKImageLoader()
    public var theme: THKMDTheme = .default

    public func setMarkdown(_ markdown: String)      // full replace, renders immediately
    public func appendMarkdownChunk(_ chunk: String)  // buffers + schedules a debounced render
    public func reset()                                // clears buffer, cancels all pending work
}

public protocol MarkdownRendering: AnyObject {
    var theme: THKMDTheme { get set }
    func render(_ markdown: String) -> [THKRenderSegment]
}

public enum THKRenderSegment {
    case text(NSAttributedString, copyableBlocks: [THKCopyableBlock])
    case table(THKTableModel)
    case diagram(mermaidSource: String)
}

public struct THKCopyableBlock {
    public let range: NSRange
    public let text: String
}

public enum THKTableColumnAlignment { case leading, center, trailing }

public struct THKTableModel {
    public let alignments: [THKTableColumnAlignment]
    public let headerCells: [NSAttributedString]
    public let rows: [[NSAttributedString]]
}

public protocol THKImageLoading {
    func load(url: URL) async -> UIImage?
}

public final class DefaultTHKImageLoader: THKImageLoading { /* URLSession + NSCache + on-disk cache */ }
```

- `setMarkdown` bypasses the debounce entirely — use it for a complete, already-final
  message.
- `appendMarkdownChunk` is the SSE path: each call appends to an internal buffer and
  (re)schedules a single debounced full re-parse/re-render (`streamingDebounceInterval`,
  default 32ms). Multiple chunks inside one window coalesce into one render — the parser
  sees the whole buffer each time, so a truncated construct (open fence, open `**`, a
  link missing its closing `)`) is just handled the way any CommonMark parser handles a
  truncated document: as literal/unterminated text until the closing syntax arrives.
- `reset()` must be called from `prepareForReuse`/`onViewRecycled` (see above). It clears
  the streaming buffer, cancels any pending debounced render, **and** cancels every
  in-flight image load in every current segment — a recycled-away view's image fetch can
  never paint onto its replacement, mirroring the existing streamed-text reuse guarantee.
- `renderer` is swappable — implement `MarkdownRendering` yourself (e.g. to add syntax
  highlighting) and assign it before calling `setMarkdown`/`appendMarkdownChunk`. It now
  returns `[THKRenderSegment]` instead of a single `NSAttributedString`: as many
  consecutive non-table blocks as possible still merge into one `.text` segment (now
  carrying its `[THKCopyableBlock]` list alongside the attributed string — see "Copy
  buttons" below); each GFM table becomes its own `.table` segment carrying a
  `THKTableModel` (column alignments, header cells, row cells — each cell itself an
  `NSAttributedString` built through the same inline-Markdown helper used everywhere
  else); a fenced code block tagged ` ```mermaid ` becomes its own `.diagram` segment
  instead (see "Mermaid diagrams" below).
- `theme: THKMDTheme` is settable and **re-renders the current content in place** when
  changed — no need to call `setMarkdown` again. It carries body/heading/link/code
  colors, the code block background + corner radius, the block quote bar/text colors,
  the table border/header colors, and body/code font sizes. Both `MarkdownRendering`
  backends read it (via the protocol's `theme` property) instead of hardcoding colors.
- `imageLoader: THKImageLoading` is settable, so a host app that already uses
  Kingfisher/SDWebImage/etc. can supply an adapter instead of `DefaultTHKImageLoader`
  (dependency-free: `URLSession` + an in-memory `NSCache` + an on-disk cache under the
  caches directory, keyed by a SHA-256 hash of the URL via `CryptoKit`). Images stay
  inline in the text flow via `THKAsyncImageTextAttachment` — a placeholder box, then the
  real bitmap scaled to fit within it once loaded, redrawn via
  `NSTextStorage.edited(.editedAttributes, range:, changeInLength: 0)` without
  relayouting the surrounding text. Tap-to-open routes through the dedicated
  `onImageTap: ((URL) -> Bool)?` (separate from `onLinkTap`, since an image attachment
  isn't a `.link` range).

### `THKTableView`

`Sources/THKMDView/THKTableView.swift` is a shared (not parser-specific) `UIScrollView`
subclass that renders a `THKTableModel` as a real grid: per-column width from each
column's widest cell (capped at a max width so one huge cell can't blow out the table),
per-column text alignment, a themed header row, hairline cell borders, and horizontal
scrolling whenever the natural content width exceeds the view's own width. It overrides
`intrinsicContentSize` to report its actual rendered height so it sizes correctly as an
arranged subview of `THKMDView`'s internal vertical `UIStackView`.

### Copy buttons

Fenced/indented code blocks and outermost block quotes (only the outermost level of a
nested `> > quote` — the same rule the rounded background fill already uses) get a small
tappable copy-to-clipboard button in their top-right corner, a `UIButton` positioned by
`THKMDView` as a direct subview of the internal `UITextView` that owns the segment. The
button's icon is drawn programmatically (`THKMDView.makeCopyIconImage()`, `UIBezierPath` +
`UIGraphicsImageRenderer`, cached after the first build) to match Lucide's "copy" icon —
the same icon Android's copy button uses — rather than the SF Symbol `doc.on.doc`, whose
different visual design didn't match across platforms. Each renderer backend tags a
copyable range's full extent with a custom
`NSAttributedString` key (`.thkCopyableCodeBlock`/`.thkCopyableBlockQuote` in
`MarkdownRenderer.swift`) and collects them into that segment's `[THKCopyableBlock]` list;
`THKMDView` places one button per entry using `NSLayoutManager.lineFragmentRect(forGlyphAt:
effectiveRange:)` for the range's first line, repositioning on every layout pass (the text
view's real width isn't settled the moment a segment is rebuilt) and rebuilding the button
set whenever the segment's content changes. Tapping a button sets
`UIPasteboard.general.string` to that block's plain display text and shows a brief
self-dismissing "Copied" label. Tables never get a copy button.

### Mermaid diagrams

A fenced code block tagged ` ```mermaid ` renders as an actual flowchart instead of literal
monospaced code text — a deliberate, scoped exception to this package's general "no
WebView" stance (`docs/RESEARCH.md` §2 kept WebView as a documented escape hatch for
exactly this kind of node type). Detection happens in both renderer backends' top-level
block loop (`renderSegments`), the same place a `Table` block is pulled out into its own
segment: a fenced block whose language/info tag is `mermaid` (case-insensitive) becomes a
`.diagram(mermaidSource:)` segment instead of a normal code block; nested inside a list or
block quote, it isn't detected (falls through to a normal code block), the same known gap
tables already have.

`THKMermaidView.swift` (shared, not parser-specific — `THKMDView.swift` binds it to
`.diagram` segments the same way it binds `THKTableView` to `.table` ones) is a `WKWebView`
loading a bundled `mermaid_template.html` that runs a vendored **mermaid.js v11.17.2**
(MIT-licensed; browser-ready UMD/IIFE build, fetched from
`https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.min.js` — see the license/
provenance comment at the top of `Sources/THKMDView/mermaid.min.js`) against the given
source. The template posts the rendered SVG's real bounding box back to Swift through a
`WKScriptMessageHandler` bridge (proxied through a weak-referencing `NSObject` so
`WKUserContentController`'s strong reference to its handler can't keep the view alive after
`stop()`/teardown), and `THKMermaidView` resizes/invalidates its `intrinsicContentSize` to
that real size (capped to the available width), mirroring the "real dimensions, not a fixed
guess" pattern `THKAsyncImageTextAttachment` already uses for images. Invalid Mermaid
syntax (or a JS error caught via the same message bridge) falls back to the raw ` ```mermaid `
source rendered as plain monospaced text with a short "diagram failed to render" note,
rather than a blank/broken WebView. `THKMDView.reset()`/segment teardown calls
`THKMermaidView.stop()`, which stops any in-flight load and removes the script message
handler — the same reuse-safety guarantee image loads and streaming text already get.

Both distributions ship `mermaid_template.html` and `mermaid.min.js`: SPM loads
`Bundle.module`, while the XCFramework loads its own framework bundle. The packaging
script verifies both files are embedded in each slice.

### Known gaps

- No syntax highlighting in code blocks (monospace + themed background/padding only).
- No incremental block-level re-parsing — every debounced render re-parses the whole
  buffer, which is fine at typical chat-message lengths.
- A `Table` nested inside a block quote or list item (rather than top-level) is not
  rendered — only top-level tables become table segments; this is a rare construct in
  LLM output. A ` ```mermaid ` fence nested the same way has the identical gap — it renders
  as a normal (non-diagram) code block instead.
