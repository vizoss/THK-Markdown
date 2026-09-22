# THKMDView (iOS)

A UIKit Swift Package that renders streaming Markdown inside a chat bubble — the kind of
view you drop into a `UITableView`/`UICollectionView` cell to show an LLM reply as it
arrives over SSE. See [`../docs/RESEARCH.md`](../docs/RESEARCH.md) for the full
architecture rationale.

`THKMDView` ships via two independent distributions that share every file except the
Markdown parser itself — see "Two distributions, one parser swapped" below.

## Requirements

- Xcode 15+ (built and tested with Xcode 26.6 / Swift 6.3)
- iOS 13+
- SPM distribution: [swift-markdown](https://github.com/swiftlang/swift-markdown)
  (Apple's CommonMark+GFM parser, used by DocC) — resolved automatically via SPM. It has
  no tagged semver releases, so `Package.swift` depends on its `main` branch;
  `Package.resolved` pins the exact commit this package was built and tested against.
- CocoaPods distribution: [Maaku](https://github.com/KristopherGBaker/Maaku) (a Swift
  wrapper around cmark-gfm), resolved automatically via CocoaPods. See "CocoaPods" below.

## Architecture in one paragraph

`THKMDView` is a `UIView` owning a vertical `UIStackView` of **segments** (see
`docs/RESEARCH.md` §9). Markdown text is parsed (by `swift-markdown` on SPM, by Maaku on
CocoaPods) into an AST, then walked to produce an ordered `[THKRenderSegment]`: as many
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

## Two distributions, one parser swapped

`THKMDView` ships two ways from this same repo:

- **Swift Package Manager** (`ios/Package.swift`) — parses with
  [swift-markdown](https://github.com/swiftlang/swift-markdown). This is the primary,
  most-tested distribution.
- **CocoaPods** (`THKMDView.podspec` at the repo root) — parses with
  [Maaku](https://github.com/KristopherGBaker/Maaku) instead, because swift-markdown has
  no CocoaPods trunk release and CocoaPods cannot resolve an SPM-only dependency for a
  pod's own compile step. Maaku wraps cmark-gfm with native GFM support (tables,
  strikethrough, task lists, autolinks), matching swift-markdown's coverage closely
  enough to keep both renderers behaviorally equivalent. Maaku is archived/unmaintained
  upstream but still installs and functions correctly (verified below); this is an
  accepted tradeoff for CocoaPods support, not an oversight.

Everything else — the public `THKMDView` API, the `MarkdownRendering` protocol, the
streaming buffer, the custom layout manager, and the rendered visual output — is shared
and meant to behave identically regardless of which distribution you use. The only
parser-specific code lives in two mutually-exclusive files that both define a type named
`DefaultMarkdownRenderer`:

- `Sources/THKMDView/SPM/SwiftMarkdownRenderer.swift` (`import Markdown`) — compiled only
  by SPM; `Package.swift`'s target excludes `CocoaPods/`.
- `Sources/THKMDView/CocoaPods/MaakuMarkdownRenderer.swift` (`import Maaku`) — compiled
  only by CocoaPods; `THKMDView.podspec`'s `exclude_files` excludes `SPM/`.

Only one of the two is ever compiled into a given build, so the duplicate type name never
collides.

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
xcodebuild test -scheme THKMDView -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

If you have more than one simulator with the same name (e.g. two "iPhone 17 Pro"
entries from different Xcode versions), disambiguate with `id=<UDID>` instead of `name=`:

```sh
xcodebuild test -scheme THKMDView -destination 'platform=iOS Simulator,id=<UDID>'
```

45 tests across three files, all passing as of this writing:

- **`Tests/THKMDViewTests/RenderTests.swift`** — feeds Markdown fixtures through
  `DefaultMarkdownRenderer` and asserts, per segment, plain-text extraction plus the
  presence of the right attribute at the right range: bold/italic font traits (including
  combined `***bold italic***`), inline code (monospace font +
  `.thkInlineCodeBackground`), all six heading levels (bold, strictly decreasing size),
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

`THKMDView` is also consumable via CocoaPods, using the podspec at the repo root
(`../THKMDView.podspec`). There is no registered CocoaPods trunk account for this project,
so install by pinning a git tag rather than `pod 'THKMDView'` from the public trunk:

```ruby
pod 'THKMDView', :git => 'https://github.com/vizoss/THK-Markdown.git', :tag => 'v0.1.0'
```

Publishing a git tag (e.g. `git tag v0.1.0 && git push origin v0.1.0`) is a manual step
the maintainer does when cutting a release — it is not done as part of any automated
process in this repo.

CocoaPods consumers get the **Maaku-backed** renderer
(`Sources/THKMDView/CocoaPods/MaakuMarkdownRenderer.swift`); SPM consumers get the
**swift-markdown-backed** one. Both implement the same `MarkdownRendering` protocol,
expose the same `THKMDView` public API, and are meant to produce equivalent visual output
for the same node-type coverage (see "Known gaps" below) — a `pod lib lint` run for real
exercises this via `THKMDView.podspec`'s `test_spec`, which points at
`Tests/THKMDViewCocoaPodsTests/MaakuRenderTests.swift`, a test suite that mirrors
`Tests/THKMDViewTests/RenderTests.swift` category-for-category against the Maaku
renderer (with one intentional divergence — see "Known gaps").

Verification commands actually run against this package (both passed):

```sh
# SPM regression check — confirms the SPM/ CocoaPods/ file split didn't break anything
cd ios
xcodebuild build -scheme THKMDView -destination 'generic/platform=iOS Simulator'
xcodebuild test -scheme THKMDView -destination 'platform=iOS Simulator,id=<UDID>'

# CocoaPods validation — compiles the pod against Maaku and runs the Maaku test spec
cd ..
pod lib lint THKMDView.podspec --test-specs=Tests --allow-warnings
```

`.github/workflows/ios-podspec-lint.yml` runs the `pod lib lint` command above in CI on
every push to `main` that touches `ios/**` or `THKMDView.podspec`. It is lint-only —
it does **not** run `pod trunk push` or publish anything, since there's no trunk account
for this project.

## Running the Example app

The example is a small UIKit app (`Example/`) — a `UITableViewController` whose cells
each simulate an SSE stream (random 2–6 character chunks, ~30ms apart, via a `Task`) into
a `THKMDView`. Sending a message cycles round-robin through a pool of six reply templates
in `Example/Sources/MockAssistantReply.swift`, each exercising a different construct
cluster: headings/emphasis/links/quotes, code blocks + task lists, nested/ordered lists,
a real table (mixed column alignment) + a cached image
(`https://picsum.photos/seed/thkmdview/480/270`), inert raw HTML, and an "everything"
showcase. The nav bar's **Theme** button toggles `THKMDView.theme` between `.default` and
a custom `THKMDTheme` on every currently visible bubble, without calling `setMarkdown`
again, to prove theming re-renders in place.

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
    case text(NSAttributedString)
    case table(THKTableModel)
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
  consecutive non-table blocks as possible still merge into one `.text` segment; each GFM
  table becomes its own `.table` segment carrying a `THKTableModel` (column alignments,
  header cells, row cells — each cell itself an `NSAttributedString` built through the
  same inline-Markdown helper used everywhere else).
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

### Known gaps

- No syntax highlighting in code blocks (monospace + themed background/padding only).
- No incremental block-level re-parsing — every debounced render re-parses the whole
  buffer, which is fine at typical chat-message lengths.
- A `Table` nested inside a block quote or list item (rather than top-level) is not
  rendered — only top-level tables become table segments; this is a rare construct in
  LLM output.
- **Maaku (CocoaPods) does not preserve a GFM ordered list's non-1 start index** — its
  `OrderedList` type (upstream, `Sources/Maaku/Core/OrderedList.swift`) receives the
  starting number during parsing but never stores it, so every ordered list renders
  renumbered from 1 regardless of source Markdown. The SPM/swift-markdown backend does
  not have this limitation. See `MaakuRenderTests.testOrderedListStartIndexIsNotPreservedByMaaku`.
