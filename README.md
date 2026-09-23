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
| iOS      | [`ios/`](ios/README.md)         | Swift    | Swift Package (source) or CocoaPods (XCFramework) |

Both iOS distributions use swift-markdown and the same renderer. CocoaPods ships a
precompiled XCFramework; Maaku is retired. Binary assets must be built and published
before remote pod installation. See [binary distribution](ios/Binary/README.md).

## Core capabilities (both platforms)

- **`setMarkdown(_:)`** — render a complete Markdown string.
- **`appendMarkdownChunk(_:)`** — append an SSE-style delta chunk; re-render is debounced
  and coalesced so a burst of small chunks doesn't cause a re-layout per token.
- **`reset()`** — clear buffered/streaming state; call this from `onViewRecycled` /
  `prepareForReuse` so a recycled cell never shows another message's tail update.
- Pluggable renderer + theme, tap handlers for links/images, GFM extensions
  (tables, strikethrough, task lists).
- P3: native alerts, basic numbered footnotes and offline inline/display math.
  Scope, configuration, safety limits and pending validation: [P3 guide](docs/P3.zh-CN.md).

## Theme configuration

All SDK-owned Markdown colors and font sizes are configured through `THKMDTheme`.
Assigning `markdownView.theme` re-renders existing content; no new `setMarkdown` call is needed.
The iOS source and binary distributions share the same renderer and settings.

| Property (same name on both platforms unless noted) | Purpose |
| --- | --- |
| `bodyTextColor` | Body, list and table body text |
| `headingTextColor` | Headings and table header text |
| `linkColor` | Links |
| `listBulletScale` (Android only) | Bullet diameter / body size, default 0.20; follows system font scale in plain lists, quotes and alerts. Configurable/persisted in the demo; iOS retains its native `•` glyph |
| `alertNoteColor`, `alertTipColor`, `alertImportantColor`, `alertWarningColor`, `alertCautionColor` | Alert title/bar colors; body/background use quote settings |
| `footnoteScale` | Footnote-reference size relative to body; default 0.75; uses `linkColor` |
| `mathScale` | Math size relative to body; default 1; uses `bodyTextColor`, transparent background |
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
| `copyFeedbackTextColor` | Copy confirmation text color |
| `copyFeedbackBackgroundColor` | Copy confirmation background, including alpha |
| `copyFeedbackFontSizeSp` / `copyFeedbackFontSize` | Copy confirmation size, Android sp / iOS pt; default 12; label dimensions adapt |

Both platforms show a brief “Copied” label below the pressed copy button. Android no longer emits an app Toast; the OS may independently show its clipboard UI. Both demos expose and persist feedback background/text colors and font size (10–24).

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
25 P2 Unicode/layout/image/scrolling fixtures and 36 P3 alert/footnote/math fixtures,
with full-text and deterministic streaming playback. Both platforms load the same
JSON sources. See the [P1 coverage and acceptance guide](docs/P1.zh-CN.md) (Chinese).
See also the [P2 acceptance guide](docs/P2.zh-CN.md). Previous/next navigation crosses
suite boundaries in P0 → P1 → P2 → P3 order, stopping only at the catalog ends (139 cases).
P1/P2/P3 are wired into the regression test entry points but have not yet been built,
tested or visually accepted; fixture coverage is not a conformance claim.

### Rendering and resource lifetime

Repeated assignment of an equal theme skips rendering. Fixed extension patterns are
compiled once. Unchanged text-only tables reuse cells (formatting, alignment and theme
are compared); image/formula cells and unsupported custom Android spans conservatively
rebind. The iOS demo coalesces height updates from content notifications instead of
polling throughout playback. Append-only ordinary paragraphs reuse completed paragraph
syntax trees and parse the remaining tail; complex block syntax, references and extensions
fall back to full-document parsing. Source validation and rendering still visit the full
document, so this is not a general-purpose incremental CommonMark parser.
Ordinary text updates retain an unchanged prefix where safe. Concurrent identical math
requests share one render; cancelling a subscriber does not cancel other subscribers.

Temporary list detachment does not clear the displayed content. Call `reset()` when
discarding/recycling Android views to destroy Mermaid WebViews; the sample activities
also clear their adapters on destruction. iOS image tasks do not retain attachments
across loading, and network task cancellation is synchronized.

Formula bitmap caching remains process-wide (default 8 MB). Configure on the main
thread/actor with `THKMDView.configureMathCache(maxBytes = bytes)` on Android or
`THKMDView.configureMathCache(maxBytes: bytes)` on iOS. Zero disables caching;
negative values are invalid. Changing the limit clears old entries; `clearMathCache()`
clears cached bitmaps without interrupting active renders or destroying the engine.
iOS uses NSCache's advisory cost limit; this is not a cap on total rendering memory.
Image caching still belongs to the injected image loader; no new image capacity API.

### Example UI

The launcher has three matching destinations on Android and iOS:

- **ShowCase 格式显示**: `ShowCaseActivity` / `ShowCaseViewController`; fixture selection,
  cross-suite previous/next, full text, play, pause, step and requirements. No chat input.
- **SSE Chat**: `SSEChatActivity` / `SSEChatViewController`; input and local simulated
  replies. Each send selects the next shared fixture and appends one chunk every
  500 ms. This is not a network SSE endpoint.
- **主题设置**: `ThemeSettingsActivity` / `ThemeSettingsViewController`; a full-page
  editor, also accessible from each demo’s header. No longer a bottom sheet.

Back returns to the previous page. Theme edits save immediately and refresh the demo
on return. Leaving a demo stops playback while keeping its received content while
the page remains on the navigation stack; ShowCase can resume with Play. Sending a
new chat message interrupts the previous mock reply without deleting its content.
Chat history is in-memory, not persisted across page destruction or app restarts.

Demo Markdown theme edits and preset selections are saved locally and restored on
the next launch (Android SharedPreferences / iOS UserDefaults), including color alpha,
font sizes, corner radius and heading scales. Select Default to save the default
theme again. Uninstalling or clearing app data removes these preferences.
Persistence belongs to the demos, not the SDK.
Default/Vibrant buttons show a blue background and checkmark when the saved values
match that preset. Custom values leave both unselected; reopening the page recomputes
selection from the saved theme rather than remembering only the last button tapped.

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
