import UIKit
import MarkdownFixtures
import THKMDView

private struct SSEReply: Decodable {
    let id: String
    let title: String
    let chunks: [String]
    let simulateFailure: Bool
    static func load() throws -> [SSEReply] {
        guard let url = Bundle.main.url(forResource: "replies", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode([SSEReply].self, from: Data(contentsOf: url))
    }
}

/// Local simulated SSE. Messages retain received prefixes independently of cell reuse.
final class SSEChatViewController: DemoMessageListViewController {
    override var pageTitle: String { "SSE Chat" }
    private let inputBar = MessageInputBar()
    private var inputBarBottomConstraint: NSLayoutConstraint!
    private let statusLabel = UILabel()
    private var fixtures: [SSEReply] = []
    private var replies: [UUID: SSEReply] = [:]
    private var states: [UUID: THKSSEState] = [:]
    private var activeID: UUID?
    private var replyIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        statusLabel.text = "30 组 AI 回复 · 输入 1–30 选题 · /停止\n第 10/20/30 组演示失败与重试"
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
        do { fixtures = try SSEReply.load() }
        catch { statusLabel.text = "用例加载失败：" + error.localizedDescription }
    }

    override func viewDidDisappear(_ animated: Bool) {
        let wasPlaying = playback != nil
        stopReply()
        super.viewDidDisappear(animated)
        if wasPlaying { statusLabel.text = "模拟 SSE · 已停止，已接收内容保留" }
    }

    private func send(_ text: String) {
        if text == "/停止" { stopReply(); statusLabel.text = "已停止，已接收内容保留"; return }
        guard !fixtures.isEmpty else { return }
        stopReply()
        followsLatestMessage = true
        appendMessage(Message(id: UUID(), role: .user, content: text))
        let selected = Int(text).flatMap { (1...fixtures.count).contains($0) ? $0 - 1 : nil } ?? (replyIndex % fixtures.count)
        let fixture = fixtures[selected]
        replyIndex += 1
        let id = UUID()
        streamedContent[id] = ""
        appendMessage(Message(id: id, role: .assistant, content: ""))
        replies[id] = fixture
        startReply(id, fixture: fixture, fail: fixture.simulateFailure)
    }

    override func configureAssistantState(_ cell: AssistantMessageCell, message: Message) {
        cell.markdownView.sseEnabled = true
        cell.markdownView.onRetry = { [weak self] in
            guard let self, let reply = self.replies[message.id] else { return }
            self.startReply(message.id, fixture: reply, fail: false)
        }
        let state = states[message.id] ?? .waiting
        cell.markdownView.setSSEState(state, errorMessage: state == .failed ? "模拟连接中断，已保留收到的内容" : nil)
    }

    private func setState(_ state: THKSSEState, id: UUID) {
        states[id] = state
        if let row = messages.firstIndex(where: { $0.id == id }),
           let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? AssistantMessageCell {
            configureAssistantState(cell, message: messages[row])
        }
        requestHeightRefresh()
    }

    private func stopReply() {
        playback?.cancel(); playback = nil
        if let id = activeID { setState(.stopped, id: id) }
        activeID = nil
    }

    private func startReply(_ id: UUID, fixture: SSEReply, fail: Bool) {
        stopReply(); activeID = id
        streamedContent[id] = ""
        if let row = messages.firstIndex(where: { $0.id == id }),
           let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? AssistantMessageCell {
            cell.markdownView.setMarkdown("")
        }
        setState(.waiting, id: id)
        statusLabel.text = "\(fixture.id) · \(fixture.title) · 思考中"
        playback = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            self?.setState(.streaming, id: id)
            for (index, chunk) in fixture.chunks.enumerated() {
                guard !Task.isCancelled, self != nil else { return }
                if fail && index == fixture.chunks.count / 2 {
                    self?.setState(.failed, id: id)
                    self?.activeID = nil; self?.playback = nil
                    self?.statusLabel.text = "\(fixture.id) · 模拟失败 · 点击回复下方重试"
                    return
                }
                self?.receiveChunk(chunk, for: id)
                self?.statusLabel.text = "模拟 SSE · \(fixture.id) · \(index + 1)/\(fixture.chunks.count) 分片"
                self?.requestHeightRefresh()
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.playback = nil
            self?.activeID = nil
            self?.setState(.completed, id: id)
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
