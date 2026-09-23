# THKMDView

*中文文档：[`README.zh-CN.md`](README.zh-CN.md)*

`THKMDView` is a cross-platform (Android / iOS) SDK for rendering **streaming Markdown**
inside chat-style UIs — the kind of view you drop into a `RecyclerView` item or a
`UITableView` cell to render an LLM's reply as it arrives over SSE, with full Markdown
formatting (headings, emphasis, links, lists, code blocks, block quotes, tables) applied
incrementally as new tokens/chunks come in.

Two independent, idiomatic implementations live side by side in this repo, sharing one
public API shape and one architecture (see [`docs/RESEARCH.md`](docs/RESEARCH.md) for the
full design rationale):

| Platform | Path                | Language | Distribution         |
|----------|---------------------|----------|-----------------------|
| Android  | [`android/`](android/README.md) | Kotlin   | Gradle module (AAR)  |
| iOS      | [`ios/`](ios/README.md)         | Swift    | Swift Package (SPM) or CocoaPods (see [`THKMDView.podspec`](THKMDView.podspec)) |

The iOS package ships two ways from the same source tree: SPM (parsed with
swift-markdown) and CocoaPods (parsed with Maaku, since swift-markdown has no CocoaPods
trunk release). Both share the same public API, streaming/rendering architecture, and are
meant to produce equivalent visual output — see [`ios/README.md`](ios/README.md#cocoapods)
for install instructions and details.

## Core capabilities (both platforms)

- **`setMarkdown(_:)`** — render a complete Markdown string.
- **`appendMarkdownChunk(_:)`** — append an SSE-style delta chunk; re-render is debounced
  and coalesced so a burst of small chunks doesn't cause a re-layout per token.
- **`reset()`** — clear buffered/streaming state; call this from `onViewRecycled` /
  `prepareForReuse` so a recycled cell never shows another message's tail update.
- Pluggable renderer + theme, tap handlers for links/images, GFM extensions
  (tables, strikethrough, task lists).

## Theme configuration

All SDK-owned Markdown colors and font sizes are configured through `THKMDTheme`.
Assigning `markdownView.theme` re-renders existing content; no new `setMarkdown` call is needed.
The iOS SPM and CocoaPods renderers share these settings.

| Property (same name on both platforms unless noted) | Purpose |
| --- | --- |
| `bodyTextColor` | Body, list and table body text |
| `headingTextColor` | Headings and table header text |
| `linkColor` | Links |
| `codeTextColor` | Inline code, code blocks and copy icons |
| `codeBackgroundColor` | Inline/code block backgrounds |
| `codeBlockCornerRadiusDp` / `codeBlockCornerRadius` | Code/quote background radius, in Android dp / iOS pt |
| `blockQuoteBarColor` | Quote bars and thematic breaks |
| `blockQuoteTextColor` | Quote text; preserves link/code colors |
| `blockQuoteBackgroundColor` | Outermost quote background, shared by nested quotes |
| `tableBorderColor` | Table grid borders |
| `tableHeaderBackgroundColor` | Table header background |
| `backgroundColor` | Entire Markdown view background; transparent by default |
| `bodyFontSizeSp` / `bodyFontSize` | Base body size, Android sp / iOS pt; default 15 |
| `codeFontSizeSp` / `codeFontSize` | Code size, Android sp / iOS pt; default 13 |
| `heading1Scale` through `heading6Scale` | Body-size multipliers; defaults 1.6, 1.4, 1.25, 1.15, 1.05, 1.0 |
| `imagePlaceholderColor` | Loading/failed image placeholder fill |
| `copyFeedbackTextColor` (iOS only) | Custom copy confirmation text |
| `copyFeedbackBackgroundColor` (iOS only) | Copy confirmation background, including alpha |
| `copyFeedbackFontSize` (iOS only) | Copy confirmation size in pt; default 12; label dimensions adapt |

Android uses a system-styled Toast for copy confirmation.

### Examples

```swift
var theme = THKMDTheme.default
theme.bodyFontSize = 18
theme.heading1Scale = 1.8
theme.imagePlaceholderColor = .lightGray
theme.copyFeedbackFontSize = 14
markdownView.theme = theme
```

```kotlin
markdownView.theme = THKMDTheme.Default.copy(
    bodyFontSizeSp = 18f,
    heading1Scale = 1.8f,
    imagePlaceholderColor = android.graphics.Color.LTGRAY
)
```

### Mermaid and scope

Mermaid uses body color/size for text, code background for node fills, table border color
for borders/edges, and quote/header backgrounds for secondary regions. Changing the theme
updates diagrams even when their source stays unchanged.

These settings cover SDK rendering, not the sample app's navigation, composer or selectors.
Default colors are fixed, not automatically dark-mode adaptive; hosts can provide an
appropriate theme. Transparent child views are compositing details; the iOS copy icon's
black template mask is tinted with the theme at display time. Mock image colors are test data.

Every field is available through the API, but the sample theme panels do not yet expose
every new field. See the commented [Android](android/thkmdview/src/main/java/com/thk/mdview/THKMDTheme.kt)
and [iOS](ios/Sources/THKMDView/THKMDTheme.swift) definitions, and the
[verification record](docs/theme-configuration.md) (Chinese).

## Status

The demos share 18 P0 regression fixtures, 60 P1 CommonMark/GFM fixtures and
25 P2 Unicode, layout, image and scrolling fixtures,
with full-text and deterministic streaming playback. Both platforms load the same
JSON sources. See the [P1 coverage and acceptance guide](docs/P1.zh-CN.md) (Chinese).
See also the [P2 acceptance guide](docs/P2.zh-CN.md). Previous/next navigation crosses
suite boundaries in P0 → P1 → P2 order, stopping only at the catalog ends.
P1/P2 are wired into the regression test entry points but have not yet been built,
tested or visually accepted; fixture coverage is not a conformance claim.

### Example UI

Demo Markdown theme edits and preset selections are saved locally and restored on
the next launch (Android SharedPreferences / iOS UserDefaults), including color alpha,
font sizes, corner radius and heading scales. Select Default to save the default
theme again. Uninstalling or clearing app data removes these preferences.
Persistence belongs to the demos, not the SDK.

The Android/iOS demo chrome uses a shared flat visual specification, independent of
the Markdown theme. Edit Android `sample/src/main/res/values/demo_ui.xml` and iOS
`DemoUI` in `Example/Sources/MockAssistantReply.swift` together: white surface,
dark text, blue accent, 14sp/pt controls, 12sp/pt captions, 18sp/pt titles,
16dp/pt horizontal gutters, 56dp/pt header, 44dp/pt controls and 68dp/pt input bar.
Fixture selection and requirements use scrollable, shadow-free custom dialogs
(screen width minus 32, maximum 560; 70% available height). Demo chrome stays light;
Markdown colors remain controlled by `THKMDTheme`. OS status bars, keyboards and
native font rasterization remain platform-specific.

Initial scaffold: project structure, build tooling, the core rendering pipeline, unit
tests, and an example app per platform. See each platform's README for how to build,
test, and run the example.

## License

[MIT](LICENSE) — see the license file; this is a placeholder default, change it if your
org requires something else.
