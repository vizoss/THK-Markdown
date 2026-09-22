import UIKit

final class MessageListViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = MessageInputBar()
    private var inputBarBottomConstraint: NSLayoutConstraint!

    private var messages: [Message] = [
        Message(
            id: UUID(),
            role: .assistant,
            content: """
            # THKMDView chat demo

            Type a message below and send it — I'll (mock) reply and stream the answer back \
            in, chunk by chunk, exactly like a real LLM response over SSE.
            """
        )
    ]

    private var heightRefreshTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "THKMDView Example"
        view.backgroundColor = .systemBackground

        setUpTableView()
        setUpInputBar()
        setUpKeyboardObservers()
        startHeightRefreshTimer() // the seeded greeting message streams in immediately too
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        heightRefreshTimer?.invalidate()
    }

    private func setUpTableView() {
        tableView.register(AssistantMessageCell.self, forCellReuseIdentifier: AssistantMessageCell.reuseIdentifier)
        tableView.register(UserMessageCell.self, forCellReuseIdentifier: UserMessageCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    private func setUpInputBar() {
        inputBar.onSend = { [weak self] text in
            self?.send(text)
        }
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)

        inputBarBottomConstraint = inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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

    // THKMDView grows via `invalidateIntrinsicContentSize()` as streamed chunks render, but
    // UITableView.automaticDimension only re-measures a row on its own layout passes — it
    // does not observe a child view's intrinsic size invalidation. While a row is streaming
    // in, nudge the table into re-measuring every tick so cells grow smoothly instead of
    // clipping/overlapping until the next unrelated layout pass. Restarted every time a new
    // assistant reply starts streaming, since that now happens repeatedly, not just once at
    // launch.
    private func startHeightRefreshTimer() {
        heightRefreshTimer?.invalidate()
        var ticksRemaining = 60 // ~9s, comfortably longer than the longest mock reply stream
        heightRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            ticksRemaining -= 1
            UIView.performWithoutAnimation {
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
            }
            if ticksRemaining <= 0 {
                timer.invalidate()
            }
        }
    }

    private func send(_ text: String) {
        appendMessage(Message(id: UUID(), role: .user, content: text))

        let delayNanoseconds = UInt64.random(in: 400_000_000...900_000_000)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            let reply = buildMockAssistantReply(for: text)
            self.appendMessage(Message(id: UUID(), role: .assistant, content: reply))
            self.startHeightRefreshTimer()
        }
    }

    private func appendMessage(_ message: Message) {
        messages.append(message)
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .none)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
    }
}

extension MessageListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        switch message.role {
        case .user:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: UserMessageCell.reuseIdentifier, for: indexPath) as? UserMessageCell else {
                return UITableViewCell()
            }
            cell.configure(text: message.content)
            return cell
        case .assistant:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: AssistantMessageCell.reuseIdentifier, for: indexPath) as? AssistantMessageCell else {
                return UITableViewCell()
            }
            cell.startStreaming(message.content)
            return cell
        }
    }
}

extension MessageListViewController: UITableViewDelegate {}
