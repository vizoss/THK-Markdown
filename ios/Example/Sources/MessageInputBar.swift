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
        backgroundColor = DemoUI.surface

        topDivider.backgroundColor = DemoUI.border
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topDivider)

        textField.attributedPlaceholder = NSAttributedString(string: "输入消息…", attributes: [.foregroundColor: DemoUI.muted])
        textField.font = .systemFont(ofSize: DemoUI.font)
        textField.textColor = DemoUI.ink
        textField.backgroundColor = DemoUI.soft
        textField.layer.cornerRadius = DemoUI.radius
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: DemoUI.control))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: DemoUI.control))
        textField.rightViewMode = .always
        textField.returnKeyType = .send
        textField.borderStyle = .none
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        sendButton.setTitle("发送", for: .normal)
        DemoUI.style(sendButton, primary: true)
        sendButton.addTarget(self, action: #selector(didTapSend), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(sendButton)

        NSLayoutConstraint.activate([
            topDivider.topAnchor.constraint(equalTo: topAnchor),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DemoUI.gutter),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            textField.heightAnchor.constraint(equalToConstant: DemoUI.control),

            sendButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DemoUI.gutter),
            sendButton.widthAnchor.constraint(equalToConstant: 64),
            sendButton.heightAnchor.constraint(equalToConstant: DemoUI.control),
            sendButton.centerYAnchor.constraint(equalTo: textField.centerYAnchor)
        ])
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 68)
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
