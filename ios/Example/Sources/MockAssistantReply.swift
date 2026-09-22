import Foundation

// Content-for-content mirror of android/sample/src/main/java/com/thk/mdview/sample/
// SampleMarkdown.kt's template functions, same order, so "the Nth message sent" produces
// matching demo content on both platforms.
private let replyTemplates: [(String) -> String] = [
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — a reply built around headings, emphasis,
        links, and quotes.

        ## A second-level heading
        ### And a third-level one

        This is *italic*, this is **bold**, this is ***bold italic***, and ~~this is
        struck through~~. Escaped markup like \\*not italic\\* stays literal.

        > A block quote — the kind of thing right before a hedge or a caveat.
        >
        > > And a nested quote inside it, for good measure.

        See the [THKMDView repo](https://github.com/vizoss/THK-Markdown) for more, or an
        autolink straight from the source: <https://github.com/vizoss/THK-Markdown>.

        ---

        That horizontal rule above separates this from the sign-off.
        """
    },
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — a reply built around code and task lists.

        Call `THKMDView.appendMarkdownChunk(chunk)` for each SSE delta. Here's a fenced
        block with a language tag:

        ```kotlin
        fun greet(name: String): String {
            return "Hello, $name!"
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
        """
    },
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — a reply built around lists, nested and not.

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

        A line with a hard break right here,\\
        continuing on the next line because of the trailing backslash above.
        """
    },
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — a real, column-aligned GFM table plus an
        inline image loaded (and cached) over the network.

        | Feature | Left | Center | Right |
        | :-- | :-- | :-: | --: |
        | Streaming | done | done | done |
        | Real table layout | done | done | done |
        | Image loading | done | done | done |
        | Theming | done | done | done |

        ![Random sample photo](https://picsum.photos/seed/thkmdview/480/270)

        Tap the image, or scroll the table sideways if it's wider than the bubble.
        """
    },
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — or, well, a tour of every Markdown
        construct THKMDView renders, since this is a mock.

        ## Headings, emphasis, and strikethrough

        This is *italic*, this is **bold**, this is ***bold italic***, and ~~this line
        is struck through~~.

        ### Inline code and a fenced code block

        Call `THKMDView.appendMarkdownChunk(chunk)` for each SSE delta. Here's a block:

        ```kotlin
        fun greet(name: String): String {
            return "Hello, $name!"
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

        ![THKMDView sample image](https://picsum.photos/seed/thkmdview/480/270)

        ## A real table, aligned and scrollable

        | Feature | Android | iOS |
        | :-- | :-: | --: |
        | Streaming | done | done |
        | Real table layout | done | done |

        ---

        That's every construct THKMDView v1 supports, streamed in one bubble.
        """
    }
]

private var nextTemplateIndex = 0

func buildMockAssistantReply(for userMessage: String) -> String {
    let template = replyTemplates[nextTemplateIndex % replyTemplates.count]
    nextTemplateIndex += 1
    return template(userMessage)
}
