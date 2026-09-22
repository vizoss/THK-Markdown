# THKMDView (Android)

A `com.android.library` module that renders streaming Markdown inside an LLM chat
bubble. See [`../docs/RESEARCH.md`](../docs/RESEARCH.md) for the full architecture
rationale (§9 covers the v1 segmented-rendering/table/image/theme design); this file
only covers building, testing, running, and the public API surface.

## Modules

- `thkmdview/` — the library (AAR). All public API lives in `com.thk.mdview`.
- `sample/` — a runnable example app: a `RecyclerView` of chat bubbles, each one
  streamed in via simulated SSE chunks, with a table+image showcase reply, a Mermaid
  flowchart reply, and a **Theme** button opening a live-editable theme settings sheet.

## Build

```sh
./gradlew :thkmdview:assembleDebug
```

## Test

```sh
./gradlew :thkmdview:testDebugUnitTest
```

Runs as fast JVM unit tests via Robolectric (no emulator needed):

- `DefaultMarkdownRendererTest` — known Markdown fixtures in, expected plain text and
  span types out: bold/italic/bold+italic, strikethrough, inline code, fenced code
  blocks (with/without a language tag), indented code blocks, headings h1–h6 (each a
  distinct size), soft vs. hard line breaks, links (inline/autolink/reference-style) +
  click callback, escaped characters, block quotes (including nested `> >`), un/ordered
  lists (including a non-1 start number and nested lists), task lists, images (become
  `AsyncImageSpan`s carrying the URL/alt text), inert-text rendering of raw HTML
  blocks/inline HTML (e.g. a `<script>` tag never gets parsed as markup), real GFM
  tables (including a column-alignment fixture and inline Markdown inside a cell), and
  the text/table segment-splitting behavior itself.
- `StreamingMarkdownBufferTest` — a chunk-fuzz test that splits a multi-construct
  fixture at several different boundary strategies (fixed size, seeded-random size,
  one character at a time) and asserts the final streamed render is character-identical
  to a single `setMarkdown` call on the whole fixture; plus a debounce-coalescing test
  and a `reset()` test.
- `THKMDViewReuseTest` — simulates `RecyclerView` reuse: starts a render mid-stream,
  calls `reset()`, binds a different message, and asserts the pre-reset pending render
  never lands on top of it; also covers segment view reuse/replacement by type, a
  `theme` change re-rendering already-set content with new colors with no fresh
  `setMarkdown` call, and — mirroring the streaming-render reuse guarantee — that an
  in-flight image load from a `reset()`-away view never paints onto its replacement.
- `DefaultTHKImageLoaderTest` — memory-cache hit avoids re-fetching, on-disk cache
  survives a fresh loader instance (no in-memory cache) without re-fetching, distinct
  URLs cache independently, a failed fetch returns null without caching, and cancelling
  the calling coroutine actually stops the load instead of letting it resolve.
- `THKTableViewTest` — column alignment maps to the correct cell `Gravity`, a missing
  alignment defaults to start, the header row is visually distinct from body rows, an
  extremely long single cell is capped rather than blowing out the table width, and row/
  column contents match the supplied data.

`DefaultMarkdownRendererTest` also covers the copy-button and Mermaid plumbing: a code
block and an outermost block quote each produce a `CopyableBlock` with the right plain
text, a nested (non-outermost) quote does not get one, and a ` ```mermaid ` fenced block
(language tag matched case-insensitively) becomes a `RenderedSegment.DiagramSegment`
carrying the diagram source rather than a normal code block. `THKMDViewReuseTest` covers
that a diagram segment gets its own `THKMermaidView` child and that `reset()` tears it
down. Actual Mermaid/SVG rendering inside the `WebView` isn't unit-tested (Robolectric
has no real rendering engine) — see "Visual verification" below for that.

## Run the sample

The sample now reads the shared `ios/Fixtures/data/p0.json` catalog (18 P0 cases) and offers case selection, full text, play, pause and single-step controls. See [P0 acceptance guide](../docs/P0.zh-CN.md) for the current workflow and explicit fallback contracts; this replaces the previous rotating mock replies described below.

```sh
./gradlew :sample:installDebug
```

Then launch `com.thk.mdview.sample/.MainActivity` on a device or emulator (or just tap
the "THKMDView Sample" icon). Sending a message cycles through a pool of mock assistant
replies — headings/emphasis/quotes, code+task lists, nested/ordered lists, a real
aligned table plus a cached network image, and a full kitchen-sink reply — each streamed
in via `appendMarkdownChunk` on random 30–80ms delays so you can watch every construct
render live. The **Theme** button opens `ThemeSettingsSheet`, a
`BottomSheetDialogFragment` exposing every `THKMDTheme` property live — see "Theme
settings sheet" below.

### Theme settings sheet

`sample/src/main/java/com/thk/mdview/sample/ThemeSettingsSheet.kt` is a
`BottomSheetDialogFragment` that exposes every configurable `THKMDTheme` property as a
live-editable control:

- **Colors** (all 11 color properties — body/heading/link/code text, code background,
  block-quote bar/text/background, table border/header background, and the view
  background) render as a row: a circular swatch preview + label. Tapping a swatch opens
  a small dialog with a curated ~16-color grid (a few neutrals, plus a light and a
  saturated variant of six hues) to pick from — there's no built-in Android color-picker
  widget, and this project deliberately avoids adding a third-party one (the same reason
  `DefaultTHKImageLoader` is hand-rolled instead of pulling in Coil), so a curated grid
  stands in for a full HSV/RGB picker.
- **Sizes** (`codeBlockCornerRadiusDp` 0–20dp, `bodyFontSizeSp`/`codeFontSizeSp` 10–24sp)
  render as a row: a label showing the current value + a `Slider`.

Two preset chips ("Default" / "Vibrant") sit above the controls and populate every
control at once from `THKMDTheme.Default`/`ALT_THEME`. Every control's change listener —
whether a swatch pick, a slider drag, or a preset tap — rebuilds a whole `THKMDTheme`
from the *current* value of all controls and passes it to `ChatAdapter.setTheme(...)`,
the same mechanism `MainActivity`'s old toolbar toggle used (`THKMDView.theme = ...`
alone re-renders already-bound bubbles, no `setMarkdown` call needed), so there's one
single code path that ever pushes a theme onto the chat. The sheet opens half-expanded
(`BottomSheetBehavior.STATE_HALF_EXPANDED` at a 0.6 ratio) rather than full screen, so
the chat stays visible behind it while dragging a slider or picking a color — the point
of live-apply is seeing the effect immediately, not just an instantaneous callback.

## Public API

```kotlin
package com.thk.mdview

class THKMDView(context: Context, attrs: AttributeSet? = null) : LinearLayout(context, attrs) {
    var streamingDebounceMs: Long = 32L
    var onLinkClick: ((String) -> Boolean)? = null
    var onImageClick: ((String) -> Boolean)? = null   // falls back to onLinkClick(imageUrl) if unset
    var theme: THKMDTheme = THKMDTheme.Default          // re-renders current content on assignment
    var imageLoader: THKImageLoader                     // defaults to DefaultTHKImageLoader(context)
    var maxContentWidthPx: Int = NO_MAX_WIDTH            // TextView.maxWidth equivalent; <= 0 = unconstrained

    fun setMarkdown(markdown: String)             // full replace, renders immediately (no debounce)
    fun appendMarkdownChunk(chunk: String)         // appends to the internal buffer, schedules a debounced re-render
    fun reset()                                    // clears the buffer, cancels pending render + in-flight image loads
    fun setMarkdownRenderer(renderer: MarkdownRenderer)
}

interface MarkdownRenderer {
    fun render(markdown: String, theme: THKMDTheme, imageBounds: ImageBounds): List<RenderedSegment>
}

sealed interface RenderedSegment {
    data class TextSegment(val spanned: CharSequence, val copyableBlocks: List<CopyableBlock> = emptyList()) : RenderedSegment
    data class TableSegment(val table: THKTableData) : RenderedSegment
    data class DiagramSegment(val mermaidSource: String) : RenderedSegment   // ```mermaid fenced block
}

data class CopyableBlock(val range: IntRange, val text: String)   // a code block, or an outermost block quote

class THKMermaidView(context: Context, attrs: AttributeSet? = null) : FrameLayout(context, attrs) {
    fun render(source: String, theme: THKMDTheme)
    fun destroy()   // called by THKMDView.reset() - tears down the WebView
}

interface THKImageLoader {
    suspend fun load(url: String): Bitmap?         // null on failure/cancellation
}

class THKTableView(context: Context, attrs: AttributeSet? = null) : HorizontalScrollView(context, attrs)

data class THKMDTheme(
    val bodyTextColor: Int, val headingTextColor: Int, val linkColor: Int,
    val codeTextColor: Int, val codeBackgroundColor: Int, val codeBlockCornerRadiusDp: Float,
    val blockQuoteBarColor: Int, val blockQuoteTextColor: Int,
    val tableBorderColor: Int, val tableHeaderBackgroundColor: Int,
    val bodyFontSizeSp: Float, val codeFontSizeSp: Float,
    val backgroundColor: Int = Color.TRANSPARENT
) {
    companion object { val Default: THKMDTheme }
}
```

### `THKMDView` is a `ViewGroup`, not a `TextView` (breaking change from v0)

As of v1, `THKMDView` is a `LinearLayout` that manages an ordered list of internal
**segments**, rebuilt on every debounced render pass (RESEARCH.md §9):

- **Text segments** — as many consecutive non-table blocks as possible (paragraphs,
  headings, lists, block quotes, code blocks, thematic breaks) still merge into one
  `Spanned` rendered by one internal `TextView`, exactly like v0. Most messages (no
  table) still render as exactly one segment.
- **Table segments** — a `THKTableView` per top-level GFM table: real per-column
  widths, GFM alignment markers (`:--`/`:-:`/`--:`) mapped to per-column text alignment,
  a themed header row, and independent horizontal scrolling (via an internal
  `HorizontalScrollView`) when the table is wider than the bubble.

Segments are matched/reused by `(index, type)` across rebuilds — a segment that's still
a text segment after a rebuild gets its text updated in place rather than the view being
torn down and recreated; a segment whose type changed (e.g. text → table) gets its child
view replaced.

Because `THKMDView` is no longer a `TextView`, XML attributes that only apply to
`TextView` (`android:textSize`, `android:textColor`, `android:textIsSelectable`,
`android:maxWidth`, …) no longer have any effect when set on
`<com.thk.mdview.THKMDView>` in a layout file. Text styling now comes from `theme`;
width-capping (e.g. so a chat bubble doesn't stretch edge-to-edge) is available via the
`maxContentWidthPx` property instead of `android:maxWidth`.

### Images

`![alt](url)` images render inline in the text flow (not as their own segment) via a
custom `ReplacementSpan` (`AsyncImageSpan`) that reserves a fixed placeholder box (240dp
× 180dp by default, shrunk to fit a narrower view) so the surrounding text never
relayouts, kicks off `imageLoader.load(url)` on a `CoroutineScope` owned by the
`THKMDView`, and redraws just that image once the bitmap arrives, scaled to fit the
reserved box. Tapping an image invokes `onImageClick` (falling back to `onLinkClick`
with the image URL if `onImageClick` is unset). `reset()` cancels every in-flight image
load the same way it cancels a pending debounced render — a recycled-away view's image
load can never paint onto the view that replaced it.

`DefaultTHKImageLoader` is dependency-free: `HttpURLConnection` on `Dispatchers.IO`, an
in-memory `LruCache` (sized to ~1/8 of `Runtime.getRuntime().maxMemory()`), and an
on-disk cache under `context.cacheDir` keyed by the SHA-256 of the URL. A host app that
already uses Coil/Glide/Kingfisher-equivalent can supply its own `THKImageLoader`
instead via `THKMDView.imageLoader`.

### Copy button on code blocks and block quotes

Every code block (fenced or indented) and every *outermost* block quote (nested `> >`
quotes don't get their own extra button — only the enclosing one does, matching the
"only the outermost quote gets the rounded background" rule) shows a small copy-to-
clipboard button in its top-right corner. A `Span` only paints into its host `TextView`'s
own canvas and isn't independently hit-testable at a specific corner, so — the same
reasoning that gave tables their own `THKTableView` — each text segment's `TextView` is
now wrapped in an internal `FrameLayout` (`TextSegmentFrame`), and copy buttons are real
`ImageButton` overlay children positioned (after layout, via `Layout.getLineTop`) at each
copyable block's top-right corner. Tapping one copies that block's plain text via
`ClipboardManager` and shows a "Copied" `Toast`. The icon is Lucide's "copy" icon
(ISC license) as a `VectorDrawable` (`res/drawable/ic_copy.xml`), tinted at runtime from
`theme.codeTextColor` so it follows the active `THKMDTheme`.

### Mermaid flowchart diagrams

A fenced code block tagged ` ```mermaid ` (language tag matched case-insensitively)
renders as an actual diagram instead of literal monospaced text, via `THKMermaidView` —
a small embedded `WebView` loading a bundled copy of `mermaid.js` and the diagram source.
This is a deliberate, scoped exception to this SDK's general "no `WebView`" stance
(RESEARCH.md §2): `WebView` was kept as a documented escape hatch for exactly this kind
of specific node type, not adopted as the general renderer — everything else still
renders through the `Spanned`/span pipeline.

`assets/mermaid.min.js` is a vendored, unmodified copy of **mermaid v11.17.2**'s browser
UMD bundle (MIT license; see `assets/mermaid.min.js.NOTICE`), loaded from a local asset
rather than a CDN so rendering works offline and never requires the host app to reach an
external network at runtime. `assets/mermaid_template.html` is the minimal page that
loads it; Android hands it the diagram source via `WebView.evaluateJavascript`, with the
source safely JSON-string-escaped (`org.json.JSONObject.quote`) so arbitrary Mermaid text
can't break out of the JS string literal.

Since the diagram's rendered size isn't known upfront, the `WebView` starts at a fixed
placeholder height; once mermaid.js renders the SVG, a small JS→Kotlin bridge
(`WebView.addJavascriptInterface`) reports the real rendered width/height back, the CSS
(`max-width: 100%`) has already capped the SVG to the `WebView`'s own width (itself capped
to the message bubble's width, same as a table), and the `WebView` is resized to the
real height and `requestLayout()`'d — mirroring how `AsyncImageSpan` swaps in an image's
real dimensions once known. Invalid Mermaid syntax is caught on the JS side and falls
back to the raw ` ```mermaid ` source shown as plain monospaced text with a "diagram
failed to render" note, rather than a blank/broken `WebView`. `THKMDView.reset()` calls
`THKMermaidView.destroy()` on any active diagram view the same way it cancels image
loads — a `WebView` is relatively heavy and must never leak across `RecyclerView`
recycling.

### Theming

`THKMDView.theme` is a settable `THKMDTheme`; assigning a new value re-renders whatever
content is currently displayed with the new colors/sizes — no fresh `setMarkdown` call
needed. `THKMDTheme.Default` matches the v0 look.

### `reset()` and RecyclerView reuse

`THKMDView.reset()` clears the streaming buffer, cancels any pending debounced render,
cancels every in-flight image load, and removes all segment child views. It **must** be
called both from `onViewRecycled` (so a message that's scrolled away stops streaming/
loading images) and again from `onBindViewHolder` before a cell starts showing a
different message (so nothing stale from the old message can land on top of the new
one's content). `sample/src/main/java/com/thk/mdview/sample/ChatAdapter.kt` is the
reference implementation: it keeps one coroutine `Job` per view holder, cancels it and
calls `reset()` in both `onBindViewHolder` (before launching the new streaming job) and
`onViewRecycled`.

## Consuming as a remote dependency (GitHub Packages)

Every push to `main` that touches `android/` runs
[`.github/workflows/android-publish.yml`](../.github/workflows/android-publish.yml),
which tests, builds, and publishes `:thkmdview`'s release AAR to this repo's
[GitHub Packages Maven registry](https://github.com/vizoss/THK-Markdown/packages) as
`com.thk.mdview:thkmdview:<VERSION_NAME>-build<run_number>` (e.g. `0.1.0-build42`) — the
build-number suffix is required because GitHub Packages refuses to let you republish an
already-existing version, so a fixed version number can't be reused across pushes. To
cut an intentional, human-chosen version instead of a build-numbered one, bump
`VERSION_NAME` in [`gradle.properties`](gradle.properties) before merging.

To depend on a published version from another project:

```kotlin
// settings.gradle.kts (or the relevant build.gradle.kts repositories block)
dependencyResolutionManagement {
    repositories {
        maven {
            url = uri("https://maven.pkg.github.com/vizoss/THK-Markdown")
            credentials {
                username = "<your-github-username>"
                password = "<a GitHub PAT with read:packages scope>" // see note below
            }
        }
    }
}
```

```kotlin
// module build.gradle.kts
dependencies {
    implementation("com.thk.mdview:thkmdview:0.1.0-build42")
}
```

**Note:** GitHub's Maven package registry requires authentication for *reads* too, even
on a public repo — an anonymous `implementation(...)` resolve will 401 without the
credentials block above. Use a [Personal Access Token](https://github.com/settings/tokens)
with the `read:packages` scope as the password (never commit it — read it from an env
var or `~/.gradle/gradle.properties` instead of hardcoding it as shown here).

## Requirements

- JDK 17
- Android SDK with `platform-34` and `build-tools;34.0.0` installed, referenced from
  `local.properties` (gitignored — create your own pointing `sdk.dir` at your SDK).
- No global Gradle install needed — use the committed `./gradlew`.

## Known limitations (v1, see RESEARCH.md §8–9 for the full roadmap)

- No syntax highlighting in code blocks (monospace + themed background/corner radius
  only).
- Code blocks wrap instead of horizontally scrolling.
- A ```` ```mermaid ```` block that's still mid-stream (fence opened, content not yet
  complete/valid) will attempt to render on every debounced pass like any other block,
  which usually means repeatedly hitting and clearing the "diagram failed to render"
  fallback until the fence closes with valid syntax — there's no "wait until the fence
  closes" special case.
- A table or a Mermaid diagram nested inside a block quote or list item isn't rendered
  as a real table/diagram (same known gap tables already had — see RESEARCH.md §8).
- Per-image accessibility is a pragmatic stand-in: a `TextView` can't expose distinct
  accessibility nodes per inline span without a custom `AccessibilityDelegate`, so a
  text segment's `contentDescription` becomes the joined alt text of every image it
  contains, rather than each image getting its own node.
- No incremental block-level re-parsing — `appendMarkdownChunk` still re-parses the
  whole accumulated buffer on each debounced render (fine at typical chat-message
  lengths; see RESEARCH.md §4/§8 if that ever needs to change).
