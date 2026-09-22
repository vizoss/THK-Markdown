# THKMDView (Android)

A `com.android.library` module that renders streaming Markdown inside an LLM chat
bubble. See [`../docs/RESEARCH.md`](../docs/RESEARCH.md) for the full architecture
rationale; this file only covers building, testing, and running.

## Modules

- `thkmdview/` — the library (AAR). All public API lives in `com.thk.mdview`.
- `sample/` — a runnable example app: a `RecyclerView` of chat bubbles, each one
  streamed in via simulated SSE chunks.

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
  span types out (bold, italic, inline code, headings, links + click callback, block
  quotes, code blocks, list items, strikethrough, image alt-text fallback, table
  fallback).
- `StreamingMarkdownBufferTest` — a chunk-fuzz test that splits a multi-construct
  fixture at several different boundary strategies (fixed size, seeded-random size,
  one character at a time) and asserts the final streamed render is character-identical
  to a single `setMarkdown` call on the whole fixture; plus a debounce-coalescing test
  and a `reset()` test.
- `THKMDViewReuseTest` — simulates `RecyclerView` reuse: starts a render mid-stream,
  calls `reset()`, binds a different message, and asserts the pre-reset pending render
  never lands on top of it.

## Run the sample

```sh
./gradlew :sample:installDebug
```

Then launch `com.thk.mdview.sample/.MainActivity` on a device or emulator (or just tap
the "THKMDView Sample" icon). It fills a `RecyclerView` with a dozen chat bubbles; each
`onBindViewHolder` streams its Markdown in via `appendMarkdownChunk` on a coroutine with
random 30–80ms delays between chunks, so you can watch headings, bold/italic, code
blocks, lists, task lists, block quotes, a table fallback, and links render live and
scroll through recycled cells to confirm nothing flickers or leaks between items.

## Public API

```kotlin
package com.thk.mdview

class THKMDView(context: Context, attrs: AttributeSet? = null) : AppCompatTextView(context, attrs) {
    var streamingDebounceMs: Long = 32L
    var onLinkClick: ((String) -> Boolean)? = null

    fun setMarkdown(markdown: String)             // full replace, renders immediately (no debounce)
    fun appendMarkdownChunk(chunk: String)         // appends to the internal buffer, schedules a debounced re-render
    fun reset()                                    // clears the buffer + cancels any pending debounced render
    fun setMarkdownRenderer(renderer: MarkdownRenderer)
}

interface MarkdownRenderer {
    fun render(markdown: String): CharSequence     // returns a Spanned
}
```

Markdown is parsed with `commonmark-java` (+ GFM tables/strikethrough/task-list-items)
and converted to a `SpannableStringBuilder` using standard Android spans — no child
views, no WebView. `appendMarkdownChunk` re-parses the *whole* accumulated buffer on
each debounced render (default 32ms, coalescing bursts of chunks into one render pass);
this is what makes an open code fence, an unclosed `**`, or a partially-typed link
render sensibly mid-stream, the same way commonmark-java handles any truncated
document.

### `reset()` and RecyclerView reuse

`THKMDView.reset()` clears the streaming buffer and cancels any pending debounced
render `Runnable`. It **must** be called both from `onViewRecycled` (so a message that's
scrolled away stops streaming) and again from `onBindViewHolder` before a cell starts
showing a different message (so a stale pending render from the old message can never
land on top of the new one's text). `sample/src/main/java/com/thk/mdview/sample/ChatAdapter.kt`
is the reference implementation: it keeps one coroutine `Job` per view holder, cancels
it and calls `reset()` in both `onBindViewHolder` (before launching the new streaming
job) and `onViewRecycled`.

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

## Known limitations (v0, see RESEARCH.md §7–8 for the full roadmap)

- GFM tables render as plain monospaced text rows, not real aligned/scrollable tables.
- Images (`![]()`) are not loaded; only alt text is rendered.
- No syntax highlighting in code blocks.
- Code blocks wrap instead of horizontally scrolling (`CodeBlockBackgroundSpan` has a
  `TODO(v1)` marking this).
