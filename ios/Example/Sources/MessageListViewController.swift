import UIKit
import THKMDView

// Shared with AssistantMessageCell/UserMessageCell. Matches android/sample's colors.xml
// (bubble_assistant_background / bubble_assistant_text / bubble_user_background / bubble_user_text).
enum SampleBubbleColors {
    static let assistantBackground = UIColor(sampleHex: 0xF0F1F3)
    static let assistantText = UIColor(sampleHex: 0x1C1C1E)
    static let userBackground = UIColor(sampleHex: 0x0A84FF)
    static let userText = UIColor(sampleHex: 0xFFFFFF)
}

extension UIColor {
    convenience init(sampleHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

final class MessageListViewController: UIViewController {
    // Demonstrates that `THKMDView.theme` is settable and re-renders in place without a
    // fresh `setMarkdown` call — toggled from the nav bar button set up in `viewDidLoad`.
    // Matches Android's ALT_THEME (android/sample/.../SampleMarkdown.kt) hex-for-hex, so
    // toggling the theme looks the same on both platforms rather than landing on iOS-only
    // arbitrarily-chosen system colors.
    private static let vibrantTheme = THKMDTheme(
        bodyTextColor: UIColor(sampleHex: 0x2B2118),
        headingTextColor: UIColor(sampleHex: 0x7A3E00),
        linkColor: UIColor(sampleHex: 0xB3541E),
        codeTextColor: UIColor(sampleHex: 0x5C3D00),
        codeBackgroundColor: UIColor(sampleHex: 0xFCE9C8),
        codeBlockCornerRadius: 10,
        blockQuoteBarColor: UIColor(sampleHex: 0xDA9A3C),
        blockQuoteTextColor: UIColor(sampleHex: 0x7A5A2E),
        blockQuoteBackgroundColor: UIColor(sampleHex: 0xFBF1DE),
        tableBorderColor: UIColor(sampleHex: 0xDA9A3C),
        tableHeaderBackgroundColor: UIColor(sampleHex: 0xF6DDB0),
        bodyFontSize: 15,
        codeFontSize: 13
    )

    private var currentTheme: THKMDTheme = .default
    // Cell reuse means a fully-streamed message's cell gets rebound every time it scrolls
    // back into view; without this, it would replay its typewriter animation from scratch on
    // every rebind instead of just showing its (already known) final content.
    private var fullyStreamedMessageIDs: Set<UUID> = []
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
        title = "THKMDView Demo"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Theme", style: .plain, target: self, action: #selector(toggleTheme)
        )

        setUpTableView()
        setUpInputBar()
        setUpKeyboardObservers()
        setUpDismissKeyboardOnTap()
        startHeightRefreshTimer() // the seeded greeting message streams in immediately too
    }

    // Tapping anywhere outside the currently-focused input (including a tap that lands on a
    // THKMDView bubble but isn't a link/image/copy button) dismisses the keyboard.
    // `cancelsTouchesInView = false` is critical: without it this recognizer would swallow
    // taps meant for table view cells, links, buttons, and the copy buttons on code blocks/
    // quotes, since a gesture recognizer with that flag set consumes the touch before it can
    // reach the view underneath. Matches Android's equivalent fix in MainActivity.kt.
    private func setUpDismissKeyboardOnTap() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardOnTap))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissKeyboardOnTap() {
        view.endEditing(true)
    }

    // Proves `THKMDView.theme` re-renders in place: every currently visible assistant
    // bubble picks up the new theme immediately, with no `setMarkdown` call.
    @objc private func toggleTheme() {
        currentTheme = (currentTheme.headingTextColor == THKMDTheme.default.headingTextColor)
            ? Self.vibrantTheme
            : .default
        for cell in tableView.visibleCells {
            (cell as? AssistantMessageCell)?.markdownView.theme = currentTheme
        }
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
        // The longest mock reply template is a couple thousand characters and streams at
        // 2-6 chars/30ms, so a slow run (small chunks) can take 20s+; a table/image reply also
        // keeps growing briefly after the text finishes while the image loads. ~45s here stays
        // comfortably ahead of both.
        var ticksRemaining = 300
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
            // Keep the growing bubble pinned to the bottom of the viewport as it streams,
            // the same way a real chat UI tracks an in-progress reply.
            if !self.messages.isEmpty {
                let lastIndexPath = IndexPath(row: self.messages.count - 1, section: 0)
                self.tableView.scrollToRow(at: lastIndexPath, at: .bottom, animated: false)
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
            cell.markdownView.theme = currentTheme
            if fullyStreamedMessageIDs.contains(message.id) {
                cell.showFullyRendered(message.content)
            } else {
                let messageID = message.id
                cell.startStreaming(message.content) { [weak self] in
                    self?.fullyStreamedMessageIDs.insert(messageID)
                }
            }
            return cell
        }
    }
}

extension MessageListViewController: UITableViewDelegate {}
