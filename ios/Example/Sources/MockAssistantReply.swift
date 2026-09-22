import Foundation

private let replyTemplates: [(String) -> String] = [
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — a look at headings, emphasis, links, and quotes.

        # Top-level heading
        ## Second level
        ### Third level

        This is *italic*, this is **bold**, this is ***bold italic***, and ~~this is
        struck through~~. Escaped characters render literally too: \\*not emphasis\\*.

        Autolinks work directly: <https://swift.org>. So do regular links: see the
        [THKMDView repo](https://github.com/vizoss/THK-Markdown) for more.

        > A block quote — the kind of thing right before a caveat.
        >
        > > And a nested quote one level deeper.
        """
    },
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — code blocks and task lists.

        ### Inline code and a fenced code block

        Call `THKMDView.appendMarkdownChunk(chunk)` for each SSE delta. Here's a block:

        ```swift
        func greet(name: String) -> String {
            "Hello, \\(name)!"
        }
        ```

        An indented code block works too:

            let indented = true

        Task list:
        - [x] Stream via SSE
        - [x] Render inline formatting
        - [x] Real GFM tables
        - [ ] Syntax highlighting (v2)
        """
    },
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — nested and ordered lists.

        Unordered, nested:
        - First point
          - A nested point with **bold** in it
          - Another nested point
        - Second point
        - Third point

        Ordered, starting past 1:
        5. Fifth step
        6. Sixth step
        7. Seventh step

        Ordered, nested inside unordered:
        - Setup
          1. Install the package
          2. Import THKMDView
          3. Drop it in a cell
        """
    },
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — a real table and a cached image.

        | Feature | Alignment | Android | iOS |
        | :--- | :---: | ---: | ---: |
        | Streaming | left | done | done |
        | Real table layout | center | done | done |
        | Cached image loading | right | done | done |
        | Theming | right | done | done |

        And here's an image, loaded asynchronously and cached on disk:

        ![THKMDView sample photo](https://picsum.photos/seed/thkmdview/480/270)
        """
    },
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — raw HTML stays inert, exactly as an
        LLM might accidentally emit it.

        This paragraph contains a literal tag: <script>alert('not executed')</script> —
        it renders as visible text, not live markup.

        Inline HTML like <span class="highlight">this</span> is inert too.

        ---

        That thematic break above separates this from a closing thought: raw HTML from
        a model should never be trusted to run.
        """
    },
    { userMessage in
        """
        Here's my answer to **"\(userMessage)"** — every construct THKMDView renders, \
        streamed in one bubble.

        # Everything, all at once

        *italic*, **bold**, ***bold italic***, ~~strikethrough~~, and `inline code`.

        ```swift
        struct Example { let value: Int }
        ```

        - Unordered item
          - Nested unordered item
        1. Ordered item
        - [x] Done
        - [ ] Not done

        > A closing block quote.

        | A | B | C |
        | :--- | :---: | ---: |
        | 1 | 2 | 3 |

        ![Sample image](https://picsum.photos/seed/thkmdview/480/270)

        See [the repo](https://github.com/vizoss/THK-Markdown) or <https://swift.org>.

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
