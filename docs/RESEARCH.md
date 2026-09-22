# THKMDView — Implementation Research & Architecture

*中文版：[`RESEARCH.zh-CN.md`](RESEARCH.zh-CN.md)*

Status: v0 (scaffold). This document is the design rationale behind the Android and iOS
scaffolds in this repo, and the list of decisions that still need a human call.

## 1. Requirements recap

- A **view component**, not a screen: `THKMDView` on Android, `THKMDView` on iOS.
- Renders **Markdown** (CommonMark + GFM: tables, strikethrough, task lists at minimum).
- Primary use case: an **LLM chat message bubble**, so it must:
  - Live inside a `RecyclerView` item / `UITableView` (or `UICollectionView`) cell and
    survive **view recycling** correctly.
  - Support **SSE streaming**: text arrives as a sequence of small deltas, and the
    rendered Markdown must update live, correctly, and cheaply as each delta arrives —
    including while a construct (a code fence, a link, a table) is *mid-arrival* and
    therefore syntactically incomplete.
- Ship with **unit tests** and a **runnable example app** per platform.

## 2. Prior art considered

| Project | Platform | Relevant idea |
|---|---|---|
| [Markwon](https://github.com/noties/Markwon) | Android | Parses Markdown (commonmark-java) into a single `Spanned`/`SpannableStringBuilder` rendered by one `TextView`. Block constructs (quotes, code blocks, lists) become custom `Span`s (`LeadingMarginSpan`, `LineBackgroundSpan`, etc.) instead of child views. This is the dominant, battle-tested pattern for Markdown-in-a-list on Android. |
| ChatGPT / Claude / Gemini web apps, `streamdown`, `react-markdown` streaming setups | Web | Buffer raw text, **re-parse the whole buffer on every chunk**, but **debounce/throttle** the re-render (typically one animation frame or ~30–50ms) rather than rendering per-token. Unterminated constructs (open code fence, open `**`) are simply left as literal text or auto-closed until the next chunk completes them — this is exactly what a CommonMark parser already does with a truncated document, so no special "partial parser" is needed. |
| `swift-markdown` (Apple/`swiftlang`) | iOS | A proper CommonMark+GFM AST (`Document`, `MarkupVisitor`) on top of `cmark`/`cmark-gfm`, analogous to `commonmark-java`. No first-party attributed-string renderer ships with it — that half we write ourselves, mirroring Markwon's span approach. |
| WebView-based renderers (render Markdown → HTML → `WKWebView`/`WebView`) | Both | Rejected as the primary path: a `WebView` per chat bubble is heavy (its own process/GPU layer, slow to create/recycle, awkward `RecyclerView`/`UITableView` height measurement, breaks native text selection/accessibility/dark-mode theming). Kept as a documented *escape hatch* for a future "render raw HTML block" node type, not the default renderer. |

## 3. Architecture decision: single attributed-text view + custom spans, not a stack of child views

Two shapes were considered for both platforms:

- **A. Single text view, AST → attributed string with custom spans/attachments**
  (Markwon's approach). One `TextView`/`UITextView` per message; block elements (code
  blocks, block quotes, tables-as-fallback, thematic breaks) are represented as custom
  spans (Android: `Span` implementations) or custom drawing (iOS: a custom
  `NSLayoutManager` that paints background rects/bars for tagged ranges) rather than
  separate child views.
- **B. Composite view, one child view per block** (a `LinearLayout`/`UIStackView` of
  paragraph labels, a table view, a code-block view, ...).

**Decision: A, with an escape hatch to B for specific node types.** Reasons:

1. **List-cell cost.** A single view per message means one measure/layout pass and one
   object to recycle, vs. N child views whose count and type vary per message. In a
   `RecyclerView`/`UITableView` scrolled at speed this is the dominant cost, not text
   layout itself.
2. **Streaming re-render cost.** Re-rendering means rebuilding one attributed
   string/`Spanned` and calling `setText`, not diffing a view tree.
3. **Proven at scale.** This is what Markwon does, and it's the closest existing analog
   to "chat message Markdown at high volume."
4. **Escape hatch, not dogma.** Some nodes genuinely want a real view — an inflight
   image that needs async load/tap-to-zoom, or a wide table that should horizontally
   scroll independently of the bubble. `THKMDView` exposes a pluggable
   `BlockRenderer`/`ExternalBlockRenderer` hook per node type so a future version can
   render *just that node* as an inline child view (Android: `ImageSpan`-with-callback
   pattern seeded by a real `View` measured off-screen; iOS: `NSTextAttachment` backed
   by a rendered `UIView` snapshot, or a custom attachment view). v0 does **not**
   implement this hook's non-text path yet — tables render as a plain monospaced
   fallback and images are not yet loaded — that's flagged as v2 work below.

## 4. Streaming / incremental rendering strategy

Chosen approach (implemented in both scaffolds):

1. `appendMarkdownChunk(chunk)` appends to an internal raw-text buffer — **no
   incremental AST diffing in v0**.
2. Each append schedules a **debounced full re-parse + re-render** of the whole buffer
   (default ~32ms, configurable). Multiple chunks arriving within the debounce window
   coalesce into a single re-render, which is what keeps this cheap even at
   token-per-few-ms streaming rates.
3. Because the parser (commonmark-java / swift-markdown, both spec-compliant CommonMark
   implementations) is handed the *whole* buffer each time, "mid-construct" text is
   handled the same way any CommonMark parser handles a truncated document — an open
   `` ``` `` fence is treated as an unterminated code block and rendered as such until
   the closing fence arrives; an open `**` is literal text until the second `**`
   arrives; a partially-typed `[link](url` is literal text until `)` closes it. No
   custom partial-Markdown grammar was needed — this matches how the web chat UIs above
   behave.
4. `reset()` cancels any pending debounced render and clears the buffer. **This must be
   called from `onViewRecycled`/cell `prepareForReuse` and again from `onBindViewHolder`
   for a fresh item** — the scaffold's unit tests (`*ReuseTest`) assert that a pending
   render from a recycled-away message can never land on the view that replaced it.
5. Deliberately deferred to v2: incremental block-level re-parsing that only
   re-renders the trailing "open" block instead of the whole buffer. Not needed for
   typical chat-message lengths (a few hundred–low thousands of characters); worth
   revisiting only if profiling on real message lengths shows it's warranted.

## 5. Public API (mirrored across platforms)

| Concept | Android (`com.thk.mdview.THKMDView`) | iOS (`THKMDView`) |
|---|---|---|
| Full render | `fun setMarkdown(markdown: String)` | `func setMarkdown(_ markdown: String)` |
| Streaming append | `fun appendMarkdownChunk(chunk: String)` | `func appendMarkdownChunk(_ chunk: String)` |
| Clear / recycle | `fun reset()` | `func reset()` |
| Debounce tuning | `var streamingDebounceMs: Long` | `var streamingDebounceInterval: TimeInterval` |
| Link tap | `var onLinkClick: ((String) -> Boolean)?` | `var onLinkTap: ((URL) -> Bool)?` |
| Custom rendering | `fun setMarkdownRenderer(renderer: MarkdownRenderer)` | `var renderer: MarkdownRendering` |

## 6. Testing strategy (implemented in the scaffold)

- **Render tests**: known Markdown fixtures → assert plain-text extraction and presence
  of the expected span/attribute types (bold, italic, inline code, heading size, link,
  block quote, code block background, list indentation).
- **Streaming/chunk-fuzz tests**: take a fixture document, split it at many different
  (including random) chunk boundaries, feed it through `appendMarkdownChunk`, and assert
  the *final* rendered output is identical to a single `setMarkdown` call on the whole
  document — this is the test that actually protects the "mid-construct" behavior above.
- **Debounce/coalescing tests**: assert N rapid chunks inside one debounce window
  produce exactly one render pass (using Robolectric's shadow looper on Android, a
  controllable clock/expectation on iOS).
- **Reuse-safety tests**: bind a view mid-stream, `reset()`/rebind as a different
  message, assert the old pending render never lands.
- Not yet included (v2 candidates): golden/snapshot pixel tests, real network SSE
  integration test, large-document performance benchmark.

## 7. Open decisions (need your call)

1. **Min OS versions.** Scaffold defaults: Android `minSdk 21`, iOS `13`. Raise either
   if you don't need that range — it simplifies some code paths (e.g. iOS 15+ has nicer
   `AttributedString`/`NSTextAttachment` APIs than 13's `NSMutableAttributedString`).
2. **License.** Defaulted to MIT (`LICENSE`) — change if your org standard differs.
3. **Package/group identifiers.** Defaulted to `com.thk.mdview` (Android) and module
   name `THKMDView` (iOS/SPM). Confirm these match your actual namespace before
   publishing anywhere.
4. **Table rendering richness.** v0 renders GFM tables as a plain monospaced fallback
   inside the single text view. A "real" table (aligned columns, horizontal scroll,
   per-cell inline styling) needs the composite-view escape hatch from §3 — worth
   prioritizing for v1 if tables are common in your LLM output.
5. **Code block syntax highlighting.** Not implemented in v0 (monospace + background
   only). Candidates: Android — Prism4j or a hand-rolled regex lexer per language;
   iOS — Splash (Swift-only) or similar. Both are pluggable behind the renderer
   interface already in place.
6. **Image loading.** Not implemented in v0 (`![]()` parses but isn't rendered). Needs
   an image-loading dependency (Coil/Glide on Android, a lightweight loader or
   `AsyncImage`-equivalent on iOS) and the composite-view/attachment escape hatch.
7. **Compose / SwiftUI wrappers.** Core is UIKit/Android View by requirement (to sit
   inside `RecyclerView`/`UITableView`). A thin `@Composable`/SwiftUI `UIViewRepresentable`
   wrapper is straightforward to add later if you also need it outside a list.
8. **Distribution.** Android now publishes to GitHub Packages (Maven) on every push to
   `main` via `.github/workflows/android-publish.yml`; iOS ships via SPM plus a
   CocoaPods podspec consumed by git tag (see `ios/README.md`). Neither is on Maven
   Central or the CocoaPods trunk registry yet — that's still open if you want it.

## 8. v1 addendum: rich rendering architecture (images, real tables, theming)

**Status: implemented on both platforms.** Decided after v0 shipped, in response to a
request for full Markdown coverage, a real (not fallback) table, cached image loading,
and a configurable color/text theme. This supersedes the "tables/images are v1, revisit
later" notes in §7.4/§7.6.

**`THKMDView` becomes a segmented vertical container, not a single text view.** A true
horizontally-scrollable table needs its own view with independent touch handling —
something a `Span`/`NSTextAttachment` fundamentally can't provide, since those are
painted content inside one text view's own canvas, not separately hit-testable views.
So rendering now walks the top-level block AST and produces a sequence of segments:

- **Text segment** — unchanged from §3/§4: as many consecutive non-table blocks as
  possible (paragraphs, headings, lists, block quotes, code blocks, thematic breaks)
  still merge into one `Spanned`/`NSAttributedString` rendered by one internal text
  view. Most messages (no table) still render as exactly one segment — the original
  single-view performance argument in §3 holds for the common case.
- **Table segment** — a new dedicated view (`THKTableView` on both platforms): real
  column layout, horizontally scrollable independent of the message bubble, themed
  border/header colors, and — since GFM table cells can contain inline Markdown — each
  cell's text goes through the same inline-span/attribute builder used everywhere else,
  not a plain-text shortcut.
- Segments are rebuilt on every debounced render pass (same buffer+debounce+full-reparse
  streaming model from §4 — only the render step's *output shape* changed). Segments are
  matched/reused by `(index, type)` across rebuilds to avoid pure destroy/recreate churn;
  perfect minimal-diffing is not a v1 requirement.

**Images stay inline** (they don't get their own segment): a custom async-loading
span/attachment reserves a fixed placeholder box sized to a max width/height (no
relayout thrash once the real image arrives — it's scaled to fit within the reserved
box), and swaps in the real bitmap once loading resolves, redrawing just that view.

**Pluggable image loading**: `THKImageLoader` (Android interface) / `THKImageLoading`
(iOS protocol) — a single `load(url) -> Bitmap?/UIImage?` method. Ships with a
dependency-free default implementation (in-memory LRU + on-disk cache, built on
`HttpURLConnection`/`URLSession` — deliberately not Coil/Kingfisher, to avoid adding a
required third-party dependency and to sidestep any repeat of the swift-markdown-style
SPM/CocoaPods distribution mismatch). `THKMDView.imageLoader` is settable, so a host app
that already uses Coil/Kingfisher/Glide can supply an adapter instead of the default.

**Theming**: an immutable `THKMDTheme` value type (colors for body/heading/link/code
text+background/block-quote bar/table border+header, font sizes) settable on
`THKMDView`, with a shipped default matching the current look.

**Accepted breaking change**: `THKMDView` is no longer literally an
`AppCompatTextView`/`UITextView` subclass — it's a container `ViewGroup`/`UIView` that
owns one or more internal text/table views. Acceptable now because the SDK has no
external consumers yet (still pre-1.0); flagged here so it isn't mistaken for an
oversight later.

### Implementation notes (what actually shipped, and known v1 gaps)

- The pluggable `MarkdownRenderer`/`MarkdownRendering` interface's `render(...)` method
  signature necessarily changed (it now returns a segment list, and on Android also
  takes the current `theme`/image-bounds config) — only `THKMDView`'s own public methods
  were kept byte-for-byte stable across v0→v1.
- Image taps: Android added a dedicated `onImageClick` (falls back to `onLinkClick` with
  the image URL if unset); iOS added `onImageTap` alongside the existing `onLinkTap`.
- A `Table` nested inside a block quote or list item (i.e. not a top-level block) isn't
  rendered as a real table on either platform — a rare-in-practice gap, not implemented.
- **iOS/CocoaPods-only gap**: Maaku (the CocoaPods-track parser) does not preserve a GFM
  ordered list's non-1 start index — its `OrderedList` type receives but discards the
  start number. This is an upstream Maaku limitation; the SPM/swift-markdown track does
  not have this gap. Covered by a test on the CocoaPods side asserting the actual
  (renumbered-from-1) behavior rather than pretending it matches SPM.
- Android's per-image accessibility label is set at the text-segment level (the whole
  `Spanned`'s content description), not attached to the individual image span — Android
  `TextView` has no built-in way to expose a per-span accessibility node without a custom
  accessibility delegate, which was judged not worth the complexity for v1.
- A real bug was caught and fixed on iOS while adding a nested-block-quote test: the
  outer quote's bar color/indent were being stamped unconditionally across the whole
  merged range, clobbering a nested quote's own (deeper) styling. Fixed with an
  "attribute already set, don't overwrite" merge rule, applied consistently.

## 9. Roadmap

- **v0 (this scaffold)** — project structure, build tooling, core Markdown→spans/
  attributed-string pipeline (bold/italic/strike/inline-code/headings/lists/blockquote/
  code-block/links/task-list), streaming buffer + debounce, reuse-safe API, unit tests,
  example app.
- **v1** — real table rendering, image loading + tap-to-zoom, theming API (colors/
  fonts/spacing as a single `Theme`/style object), link preview hook.
- **v2** — syntax highlighting, incremental block-level re-parse (only if profiling
  shows the full-buffer re-parse is a real bottleneck at your message lengths),
  Compose/SwiftUI wrappers.
- **v3** — publishing pipeline (Maven Central + SPM registry/CocoaPods), golden/
  snapshot visual regression tests, accessibility audit (VoiceOver/TalkBack pass over
  every node type).
