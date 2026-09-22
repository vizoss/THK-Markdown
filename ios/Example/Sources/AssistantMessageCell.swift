import UIKit
import THKMDView

final class AssistantMessageCell: UITableViewCell {
    static let reuseIdentifier = "AssistantMessageCell"

    let markdownView = THKMDView()
    private let bubbleView = UIView()
    private var streamTask: Task<Void, Never>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        selectionStyle = .none
        markdownView.onLinkTap = { url in
            print("Link tapped: \(url)")
            return true
        }
        markdownView.onImageTap = { url in
            print("Image tapped: \(url)")
            return true
        }
        // Matches Android's assistant bubble (item_message_assistant.xml: a MaterialCardView,
        // 14dp corner radius, bubble_assistant_background, 14dp padding around THKMDView).
        bubbleView.backgroundColor = SampleBubbleColors.assistantBackground
        bubbleView.layer.cornerRadius = 14
        bubbleView.clipsToBounds = true
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        markdownView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(markdownView)

        NSLayoutConstraint.activate([
            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            markdownView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            markdownView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14),
            markdownView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 14),
            markdownView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -14)
        ])
    }

    // This is the reference implementation the README points to: cancel the in-flight
    // stream simulation and reset the view's buffer/pending-render state before the cell
    // gets rebound to a different row.
    override func prepareForReuse() {
        super.prepareForReuse()
        streamTask?.cancel()
        streamTask = nil
        markdownView.reset()
    }

    /// `onFinished` fires once, on the main actor, only when the chunk loop runs all the way
    /// to the end on its own — never when `prepareForReuse`/a later `startStreaming` call
    /// cancels this task first. That's what lets the caller distinguish "genuinely finished
    /// streaming" from "recycled mid-stream" so it knows which messages to render instantly
    /// (no re-typing animation) the next time their cell is bound.
    func startStreaming(_ fullMarkdown: String, onFinished: @escaping () -> Void) {
        streamTask?.cancel()
        markdownView.reset()

        let view = markdownView
        streamTask = Task {
            var remaining = Substring(fullMarkdown)
            while !remaining.isEmpty {
                if Task.isCancelled { return }
                let chunkSize = Int.random(in: 2...6)
                let end = remaining.index(remaining.startIndex, offsetBy: chunkSize, limitedBy: remaining.endIndex) ?? remaining.endIndex
                let chunk = String(remaining[remaining.startIndex..<end])
                remaining = remaining[end...]
                await MainActor.run {
                    view.appendMarkdownChunk(chunk)
                }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            if Task.isCancelled { return }
            await MainActor.run {
                onFinished()
            }
        }
    }

    /// Used instead of `startStreaming` when this row's message already finished streaming
    /// once before (tracked by `MessageListViewController`) and its cell is simply scrolling
    /// back into view via normal `UITableView` reuse — shows the full content immediately
    /// rather than re-running the typewriter animation from scratch.
    func showFullyRendered(_ fullMarkdown: String) {
        streamTask?.cancel()
        streamTask = nil
        markdownView.reset()
        markdownView.setMarkdown(fullMarkdown)
    }
}
