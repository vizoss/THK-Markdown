import UIKit

final class UserMessageCell: UITableViewCell {
    static let reuseIdentifier = "UserMessageCell"

    private let bubbleView = UIView()
    private let label = UILabel()

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
        backgroundColor = .clear

        // Matches Android's user bubble (item_message_user.xml: cardCornerRadius 14dp,
        // bubble_user_background, uniform 14dp padding around the text).
        bubbleView.backgroundColor = SampleBubbleColors.userBackground
        bubbleView.layer.cornerRadius = 14
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        label.numberOfLines = 0
        label.textColor = SampleBubbleColors.userText
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(label)

        let maxWidthConstraint = bubbleView.widthAnchor.constraint(
            lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75
        )

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            maxWidthConstraint,

            label.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -14),
            label.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14)
        ])
    }

    func configure(text: String) {
        label.text = text
    }
}
