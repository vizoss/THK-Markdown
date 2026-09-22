import UIKit
import THKMDView

final class AssistantMessageCell: UITableViewCell {
    static let reuseIdentifier = "AssistantMessageCell"

    let markdownView = THKMDView()
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
        markdownView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(markdownView)
        NSLayoutConstraint.activate([
            markdownView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            markdownView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            markdownView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            markdownView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
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

    func startStreaming(_ fullMarkdown: String) {
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
        }
    }
}
