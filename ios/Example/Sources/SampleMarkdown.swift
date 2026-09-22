import Foundation

enum SampleMarkdown {
    static let all: [String] = [
        """
        # Welcome to THKMDView

        This message streams in over **SSE**, a few characters at a time, exactly like an \
        LLM chat reply. Formatting like _italics_, **bold**, and `inline code` resolves \
        correctly even while it's still mid-arrival.

        Read more in the [project README](https://github.com/example/thk-markdown).
        """,
        """
        ## Code block

        Here's a fenced code block, rendered monospaced with a background:

        ```swift
        func fibonacci(_ n: Int) -> Int {
            n <= 1 ? n : fibonacci(n - 1) + fibonacci(n - 2)
        }
        ```

        And some ~~strikethrough~~ text right after it.
        """,
        """
        ### Lists

        Unordered:
        - First item
        - Second item
        - Third item with `inline code`

        Ordered:
        1. Step one
        2. Step two
        3. Step three

        Tasks:
        - [x] Parse Markdown into an AST
        - [x] Build an attributed string
        - [ ] Ship syntax highlighting (v2)
        """,
        """
        > "The best way to predict the future is to invent it."
        >
        > A block quote, indented and marked with a left bar, can span
        > multiple lines and even multiple paragraphs.

        Back to a regular paragraph after the quote.
        """,
        """
        #### A GFM table (v0 fallback)

        | Feature | Status |
        | --- | --- |
        | Bold / italic | Done |
        | Code blocks | Done |
        | Tables | Plain-text fallback |
        | Images | Deferred |

        Tables render as plain monospaced rows in v0 — a real aligned table view is v1 work.
        """
    ]
}
