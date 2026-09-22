# THKMDView

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
| iOS      | [`ios/`](ios/README.md)         | Swift    | Swift Package (SPM)  |

## Core capabilities (both platforms)

- **`setMarkdown(_:)`** — render a complete Markdown string.
- **`appendMarkdownChunk(_:)`** — append an SSE-style delta chunk; re-render is debounced
  and coalesced so a burst of small chunks doesn't cause a re-layout per token.
- **`reset()`** — clear buffered/streaming state; call this from `onViewRecycled` /
  `prepareForReuse` so a recycled cell never shows another message's tail update.
- Pluggable renderer + theme, tap handlers for links/images, GFM extensions
  (tables, strikethrough, task lists).

## Status

Initial scaffold: project structure, build tooling, the core rendering pipeline, unit
tests, and an example app per platform. See each platform's README for how to build,
test, and run the example.

## License

[MIT](LICENSE) — see the license file; this is a placeholder default, change it if your
org requires something else.
