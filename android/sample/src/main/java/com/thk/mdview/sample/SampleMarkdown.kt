package com.thk.mdview.sample

val SAMPLE_MARKDOWN_DOCS: List<String> = listOf(
    """
        # THKMDView demo

        This bubble was rendered by **THKMDView**, streamed in over simulated SSE
        chunks the same way an LLM reply would arrive.

        It supports *italic*, **bold**, and `inline code`, plus links like
        [the project README](https://example.com/thk-markdown).

        > A block quote can show up mid-answer, e.g. to cite a source.

        Steps to reproduce:
        1. Open the RecyclerView
        2. Scroll past this item and back
        3. Confirm the text never flickers or shows another message's tail
    """.trimIndent(),
    """
        ## Code block example

        ```
        fun appendMarkdownChunk(chunk: String) {
            buffer.append(chunk)
        }
        ```

        Unordered list:
        - streaming buffer
        - debounced re-render
        - reuse-safe reset()

        Task list:
        - [x] parse with commonmark-java
        - [x] convert AST to spans
        - [ ] syntax highlighting (v2)
    """.trimIndent(),
    """
        ### A GFM table (v0 fallback)

        | Feature | Status |
        | --- | --- |
        | Tables | plain text fallback |
        | Images | alt text only |
        | Streaming | debounced re-render |

        ~~This line is struck through~~ to show GFM strikethrough support.
    """.trimIndent()
)
