import Foundation

func buildMockAssistantReply(for userMessage: String) -> String {
    """
    Here's my answer to **"\(userMessage)"** — or, well, a tour of every Markdown
    construct THKMDView renders, since this is a mock.

    ## Headings, emphasis, and strikethrough

    This is *italic*, this is **bold**, this is ***bold italic***, and ~~this line
    is struck through~~.

    ### Inline code and a fenced code block

    Call `THKMDView.appendMarkdownChunk(chunk)` for each SSE delta. Here's a block:

    ```swift
    func greet(name: String) -> String {
        "Hello, \\(name)!"
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
    - [ ] Ship real table layout (v1)

    ## Quotes, links, and an image

    > A block quote — the kind of thing right before a hedge or a caveat.

    See the [THKMDView repo](https://github.com/vizoss/THK-Markdown) for more, and
    here's an image (v0 only renders its alt text, no network fetch):

    ![THKMDView logo](https://example.com/thkmdview-logo.png)

    ## A table (v0 renders this as a plain-text fallback)

    | Feature | Android | iOS |
    | --- | --- | --- |
    | Streaming | done | done |
    | Real table layout | v1 | v1 |

    ---

    That's every construct THKMDView v0 supports, streamed in one bubble.
    """
}
