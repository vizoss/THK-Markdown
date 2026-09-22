import UIKit

final class MessageInputBar: UIView {
    var onSend: ((String) -> Void)?

    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let topDivider = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .systemBackground

        topDivider.backgroundColor = .separator
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topDivider)

        textField.placeholder = "Message…"
        textField.returnKeyType = .send
        textField.borderStyle = .roundedRect
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        sendButton.setTitle("Send", for: .normal)
        sendButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(sendButton)

        NSLayoutConstraint.activate([
            topDivider.topAnchor.constraint(equalTo: topAnchor),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textField.heightAnchor.constraint(equalToConstant: 36),

            sendButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: textField.centerYAnchor)
        ])
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    @objc private func didTapSend() {
        let trimmed = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend?(trimmed)
        textField.text = ""
    }
}

extension MessageInputBar: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapSend()
        return true
    }
}
