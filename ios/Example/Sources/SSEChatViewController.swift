import UIKit
import MarkdownFixtures

/// Local simulated SSE. Messages retain received prefixes independently of cell reuse.
final class SSEChatViewController: DemoMessageListViewController {
    override var pageTitle: String { "SSE Chat" }
    private let inputBar = MessageInputBar()
    private var inputBarBottomConstraint: NSLayoutConstraint!
    private let statusLabel = UILabel()
    private var fixtures: [MarkdownFixture] = []
    private var replyIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        statusLabel.text = "本地模拟 SSE · 发送消息开始"
        statusLabel.font = .systemFont(ofSize: DemoUI.caption)
        statusLabel.textColor = DemoUI.muted
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: demoHeader.bottomAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: DemoUI.gutter),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -DemoUI.gutter),
            statusLabel.heightAnchor.constraint(equalToConstant: 48)
        ])
        setUpInputBar()
        setUpKeyboardObservers()
        setUpDismissKeyboardOnTap()
        do { fixtures = try MarkdownFixture.loadAll() }
        catch { statusLabel.text = "用例加载失败：" + error.localizedDescription }
    }

    override func viewDidDisappear(_ animated: Bool) {
        let wasPlaying = playback != nil
        super.viewDidDisappear(animated)
        if wasPlaying { statusLabel.text = "模拟 SSE · 已停止，已接收内容保留" }
    }

    private func send(_ text: String) {
        guard !fixtures.isEmpty else { return }
        playback?.cancel()
        followsLatestMessage = true
        appendMessage(Message(id: UUID(), role: .user, content: text))
        let fixture = fixtures[replyIndex % fixtures.count]
        replyIndex += 1
        let id = UUID()
        streamedContent[id] = ""
        appendMessage(Message(id: id, role: .assistant, content: ""))
        playback = Task { @MainActor [weak self] in
            for (index, chunk) in fixture.chunks.enumerated() {
                guard !Task.isCancelled, self != nil else { return }
                self?.receiveChunk(chunk, for: id)
                self?.statusLabel.text = "模拟 SSE · \(fixture.id) · \(index + 1)/\(fixture.chunks.count) 分片"
                self?.requestHeightRefresh()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.playback = nil
            self?.statusLabel.text = "模拟 SSE · \(fixture.id) · 已完成"
            self?.requestHeightRefresh()
        }
        requestHeightRefresh()
    }

    private func setUpInputBar() {
        inputBar.onSend = { [weak self] text in
            self?.send(text)
        }
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)

        inputBarBottomConstraint = inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            inputBarBottomConstraint
        ])
    }

    private func setUpKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let curveRaw = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }

        let endFrameInView = view.convert(endFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - endFrameInView.minY - view.safeAreaInsets.bottom)

        inputBarBottomConstraint.constant = -overlap

        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
    }


    private func setUpDismissKeyboardOnTap() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardOnTap))
        tapGesture.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissKeyboardOnTap() {
        view.endEditing(true)
    }


}
