import UIKit
import THKMDView

final class AssistantMessageCell: UITableViewCell {
    static let reuseIdentifier = "AssistantMessageCell"

    let markdownView = THKMDView()
    private let bubbleView = UIView()

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

    // The controller owns streaming; reuse only clears this view's pending render.
    override func prepareForReuse() {
        super.prepareForReuse()
        markdownView.reset()
    }

    /// Restore exactly the prefix received so far, including after scrolling back onscreen.
    func showContent(_ markdown: String) {
        markdownView.reset()
        markdownView.setMarkdown(markdown)
    }
}
