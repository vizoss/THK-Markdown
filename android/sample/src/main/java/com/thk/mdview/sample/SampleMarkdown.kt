package com.thk.mdview.sample

import com.thk.mdview.THKMDTheme

/** A visibly non-default theme so the sample can prove `THKMDView.theme = ...` alone
 *  re-renders already-bound bubbles, with no fresh `setMarkdown` call. */
val ALT_THEME: THKMDTheme = THKMDTheme(
    bodyTextColor = 0xFF2B2118.toInt(),
    headingTextColor = 0xFF7A3E00.toInt(),
    linkColor = 0xFFB3541E.toInt(),
    codeTextColor = 0xFF5C3D00.toInt(),
    codeBackgroundColor = 0xFFFCE9C8.toInt(),
    codeBlockCornerRadiusDp = 10f,
    blockQuoteBarColor = 0xFFDA9A3C.toInt(),
    blockQuoteTextColor = 0xFF7A5A2E.toInt(),
    blockQuoteBackgroundColor = 0xFFFBF1DE.toInt(),
    tableBorderColor = 0xFFDA9A3C.toInt(),
    tableHeaderBackgroundColor = 0xFFF6DDB0.toInt(),
    bodyFontSizeSp = 15f,
    codeFontSizeSp = 13f
)

val GREETING_MARKDOWN: String = """
    # THKMDView chat demo

    Type a message below and send it — I'll (mock) reply and stream the answer back
    in, chunk by chunk, exactly like a real LLM response over SSE.
""".trimIndent()

/** Deterministic per-seed image URL, good for proving repeat sends hit the image cache. */
private const val SAMPLE_IMAGE_URL = "https://picsum.photos/seed/thkmdview/480/270"

private fun headingsAndQuotesReply(userMessage: String): String = """
    Here's my answer to **"$userMessage"** — a reply built around headings, emphasis,
    links, and quotes.

    ## A second-level heading
    ### And a third-level one

    This is *italic*, this is **bold**, this is ***bold italic***, and ~~this is
    struck through~~. Escaped markup like \*not italic\* stays literal.

    > A block quote — the kind of thing right before a hedge or a caveat.
    >
    > > And a nested quote inside it, for good measure.

    See the [THKMDView repo](https://github.com/vizoss/THK-Markdown) for more, or an
    autolink straight from the source: <https://github.com/vizoss/THK-Markdown>.

    ---

    That horizontal rule above separates this from the sign-off.
""".trimIndent()

private fun codeAndTasksReply(userMessage: String): String = """
    Here's my answer to **"$userMessage"** — a reply built around code and task lists.

    Call `THKMDView.appendMarkdownChunk(chunk)` for each SSE delta. Here's a fenced
    block with a language tag:

    ```kotlin
    fun greet(name: String): String {
        return "Hello, ${'$'}name!"
    }
    ```

    And one with no language tag:

    ```
    plain fenced content, no syntax highlighting
    ```

    An indented code block:

        indented().code().block()

    Progress on this feature:
    - [x] Stream via SSE
    - [x] Render inline formatting
    - [ ] Ship syntax highlighting (still deferred)
""".trimIndent()

private fun listsReply(userMessage: String): String = """
    Here's my answer to **"$userMessage"** — a reply built around lists, nested and not.

    Unordered, with a nested sub-list:
    - First point
    - Second point with **bold** in it
      - a nested point
      - another nested point
    - Third point

    Ordered, starting from a non-1 number:
    5. Parse the Markdown
    6. Convert it to spans
    7. Render it live as chunks arrive

    A line with a hard break right here,\
    continuing on the next line because of the trailing backslash above.
""".trimIndent()

private fun tableAndImageReply(userMessage: String): String = """
    Here's my answer to **"$userMessage"** — a real, column-aligned GFM table plus an
    inline image loaded (and cached) over the network.

    | Feature | Left | Center | Right |
    | :-- | :-- | :-: | --: |
    | Streaming | done | done | done |
    | Real table layout | done | done | done |
    | Image loading | done | done | done |
    | Theming | done | done | done |

    ![Random sample photo]($SAMPLE_IMAGE_URL)

    Tap the image, or scroll the table sideways if it's wider than the bubble.
""".trimIndent()

private fun kitchenSinkReply(userMessage: String): String = """
    Here's my answer to **"$userMessage"** — or, well, a tour of every Markdown
    construct THKMDView renders, since this is a mock.

    ## Headings, emphasis, and strikethrough

    This is *italic*, this is **bold**, this is ***bold italic***, and ~~this line
    is struck through~~.

    ### Inline code and a fenced code block

    Call `THKMDView.appendMarkdownChunk(chunk)` for each SSE delta. Here's a block:

    ```kotlin
    fun greet(name: String): String {
        return "Hello, ${'$'}name!"
    }
    ```

    ## Lists

    Unordered:
    - First point
    - Second point with **bold** in it
    - Third point

    Ordered:
    1. Parse the Markdown
    2. Convert it to spans
    3. Render it live as chunks arrive

    Task list:
    - [x] Stream via SSE
    - [x] Render inline formatting
    - [x] Ship real table layout (v1)

    ## Quotes, links, and an image

    > A block quote — the kind of thing right before a hedge or a caveat.

    See the [THKMDView repo](https://github.com/vizoss/THK-Markdown) for more, and
    here's a real loaded image:

    ![THKMDView sample image]($SAMPLE_IMAGE_URL)

    ## A real table, aligned and scrollable

    | Feature | Android | iOS |
    | :-- | :-: | --: |
    | Streaming | done | done |
    | Real table layout | done | done |

    ---

    That's every construct THKMDView v1 supports, streamed in one bubble.
""".trimIndent()

private fun mermaidDiagramReply(userMessage: String): String = """
    Here's my answer to **"$userMessage"** — a real rendered Mermaid flowchart, via the
    embedded-`WebView` escape hatch (see RESEARCH.md §2), not literal monospaced text.

    ```mermaid
    flowchart LR
        A[User sends message] --> B{THKMDView}
        B --> C[Parse Markdown]
        C --> D[Render segments]
        D --> E[Display in chat]
    ```

    And a quote you can copy via the corner button, right next to a code block you can
    copy the same way:

    > Every `mermaid` fence gets its own diagram segment instead of a code block.

    ```kotlin
    // Also copyable via the button in its top-right corner
    fun renderDiagram(source: String) = THKMermaidView(context).render(source, theme)
    ```
""".trimIndent()

private val REPLY_TEMPLATES: List<(String) -> String> = listOf(
    ::headingsAndQuotesReply,
    ::codeAndTasksReply,
    ::listsReply,
    ::tableAndImageReply,
    ::kitchenSinkReply,
    ::mermaidDiagramReply
)

private var nextReplyIndex = 0

/**
 * Builds a fake "LLM reply" from a pool of templates, round-robining through them so
 * repeated sends show off different Markdown constructs instead of the same reply
 * every time. Each template still opens with an acknowledgement of [userMessage].
 */
fun buildMockAssistantReply(userMessage: String): String {
    val template = REPLY_TEMPLATES[nextReplyIndex % REPLY_TEMPLATES.size]
    nextReplyIndex++
    return template(userMessage)
}
