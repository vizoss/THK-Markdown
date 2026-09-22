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

`THKMDView` is a `UIView` wrapping a single non-scrolling, non-editable `UITextView`
pinned to its edges. Markdown text is parsed by `swift-markdown` into an AST, then walked
by `AttributedStringVisitor` (in `Sources/THKMDView/MarkdownRenderer.swift`) to build one
`NSAttributedString` — bold/italic become font traits, links become `.link` attributes,
lists become paragraph-style indent + a literal marker glyph. Constructs with no built-in
`NSAttributedString` representation (inline code background, code block background,
block quote bar) are tagged with custom attribute keys and painted by
`THKBackgroundLayoutManager`, a custom `NSLayoutManager` subclass that overrides
`drawBackground(forGlyphRange:at:)`. This mirrors Markwon's approach on Android: one
text view, one attributed string, custom spans/drawing for block constructs — not a
composite view tree.

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

30 tests across three files, all passing as of this writing:

- **`Tests/THKMDViewTests/RenderTests.swift`** — feeds Markdown fixtures through
  `DefaultMarkdownRenderer` and asserts plain-text extraction plus the presence of the
  right attribute at the right range: bold/italic font traits (including combined
  `***bold italic***`), inline code (monospace font + `.thkInlineCodeBackground`),
  heading size/boldness (and that deeper levels are smaller), a link's `.link` URL, a
  block quote's `.thkBlockQuoteBar` + indent, a code block's monospace font +
  `.thkCodeBlockBackground`, strikethrough, ordered/unordered/task lists, and the
  plain-monospace GFM table fallback. Also covers two "mid-arrival" cases directly (an
  unterminated code fence, an unterminated `**`) to confirm they don't crash and degrade
  sensibly.
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
for the same v0 node-type coverage (see "What's deferred to v1/v2" below) — a `pod lib
lint` run for real exercises this via `THKMDView.podspec`'s `test_spec`, which points at
`Tests/THKMDViewCocoaPodsTests/MaakuRenderTests.swift`, a test suite that mirrors
`Tests/THKMDViewTests/RenderTests.swift` category-for-category against the Maaku
renderer.

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
a `THKMDView`, covering headings, bold/italic, inline code, a code block, strikethrough,
ordered/unordered/task lists, a block quote, a link, and a GFM table fallback.

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
    public var renderer: MarkdownRendering = DefaultMarkdownRenderer()

    public func setMarkdown(_ markdown: String)      // full replace, renders immediately
    public func appendMarkdownChunk(_ chunk: String)  // buffers + schedules a debounced render
    public func reset()                                // clears buffer, cancels pending render
}

public protocol MarkdownRendering {
    func render(_ markdown: String) -> NSAttributedString
}
```

- `setMarkdown` bypasses the debounce entirely — use it for a complete, already-final
  message.
- `appendMarkdownChunk` is the SSE path: each call appends to an internal buffer and
  (re)schedules a single debounced full re-parse/re-render (`streamingDebounceInterval`,
  default 32ms). Multiple chunks inside one window coalesce into one render — the parser
  sees the whole buffer each time, so a truncated construct (open fence, open `**`, a
  link missing its closing `)`) is just handled the way any CommonMark parser handles a
  truncated document: as literal/unterminated text until the closing syntax arrives.
- `reset()` must be called from `prepareForReuse`/`onViewRecycled` (see above).
- `renderer` is swappable — implement `MarkdownRendering` yourself (e.g. to add syntax
  highlighting or a themed `DefaultMarkdownRenderer(baseFont:)`) and assign it before
  calling `setMarkdown`/`appendMarkdownChunk`.

### What's deferred to v1/v2 (see `docs/RESEARCH.md` §8)

GFM tables render as plain monospaced text rows, not a real aligned table; images parse
but aren't loaded (alt text renders as plain text); no syntax highlighting; no
incremental block-level re-parsing (every debounced render re-parses the whole buffer,
which is fine at typical chat-message lengths).
