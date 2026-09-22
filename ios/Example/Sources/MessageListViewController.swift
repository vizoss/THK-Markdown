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
    // fresh `setMarkdown` call — edited live from the settings sheet opened by the nav bar
    // button set up in `viewDidLoad`. Matches Android's ALT_THEME (android/sample/.../
    // SampleMarkdown.kt) hex-for-hex, so this quick-select preset looks the same on both
    // platforms rather than landing on iOS-only arbitrarily-chosen system colors.
    static let vibrantTheme = THKMDTheme(
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
    // Keep SSE progress independent of cell visibility and reuse.
    private var streamedContent: [UUID: String] = [:]
    private var streamTasks: [UUID: Task<Void, Never>] = [:]
    private var followsLatestMessage = true
    private var finalHeightRefreshes = 0
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
            title: "Theme", style: .plain, target: self, action: #selector(openThemeSettings)
        )

        setUpTableView()
        setUpInputBar()
        setUpKeyboardObservers()
        setUpDismissKeyboardOnTap()
        for message in messages where message.role == .assistant {
            startStreaming(message)
        }
    }

    // Tapping the message list (not the whole screen - see below) dismisses the keyboard,
    // matching Android's equivalent fix in MainActivity.kt (a GestureDetector scoped to
    // the RecyclerView only, not the whole Activity, for the same reason).
    // `cancelsTouchesInView = false` is critical: without it this recognizer would swallow
    // taps meant for table view cells, links, and the copy buttons on code blocks/quotes,
    // since a gesture recognizer with that flag set consumes the touch before it can reach
    // the view underneath.
    //
    // This must be attached to `tableView`, not `view` - attaching it to the whole screen
    // previously meant a tap on the Send button (in the separate `inputBar`) also fired
    // `endEditing(true)`, and the resulting keyboard-dismiss animation shifted the input
    // bar's bottom constraint mid-touch, moving the Send button out from under the tap
    // before UIKit could register it as a completed "touch up inside" - the keyboard closed
    // but the message never sent. Scoping to `tableView` means a tap that starts on the
    // input bar never reaches this recognizer at all.
    private func setUpDismissKeyboardOnTap() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardOnTap))
        tapGesture.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissKeyboardOnTap() {
        view.endEditing(true)
    }

    // Opens the settings sheet with every THKMDTheme control live-bound to the currently
    // visible bubbles — see ThemeSettingsViewController.
    @objc private func openThemeSettings() {
        let sheet = ThemeSettingsViewController(
            theme: currentTheme,
            presets: [("Default", .default), ("Vibrant", Self.vibrantTheme)]
        )
        sheet.onThemeChange = { [weak self] theme in
            self?.applyTheme(theme)
        }
        if let sheetPresentation = sheet.sheetPresentationController {
            sheetPresentation.detents = [.medium(), .large()]
            sheetPresentation.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    // Proves `THKMDView.theme` re-renders in place: every currently visible assistant
    // bubble picks up the new theme immediately, with no `setMarkdown` call. Reused by both
    // the settings sheet's live edits and its preset quick-select buttons.
    private func applyTheme(_ theme: THKMDTheme) {
        currentTheme = theme
        for cell in tableView.visibleCells {
            (cell as? AssistantMessageCell)?.markdownView.theme = theme
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        heightRefreshTimer?.invalidate()
        streamTasks.values.forEach { $0.cancel() }
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
        guard heightRefreshTimer == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            // Don't fight a drag/deceleration with self-sizing row updates. The next
            // idle tick catches up using the message's latest streamed content.
            guard !self.tableView.isTracking, !self.tableView.isDragging,
                  !self.tableView.isDecelerating else { return }
            let oldOffset = self.tableView.contentOffset
            UIView.performWithoutAnimation {
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
                self.tableView.layoutIfNeeded()
                if self.followsLatestMessage {
                    self.scrollToLatestMessage()
                } else {
                    self.tableView.setContentOffset(oldOffset, animated: false)
                }
            }
            if self.streamTasks.isEmpty {
                self.finalHeightRefreshes -= 1
                if self.finalHeightRefreshes <= 0 {
                    timer.invalidate()
                    self.heightRefreshTimer = nil
                }
            }
        }
        heightRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startStreaming(_ message: Message) {
        streamedContent[message.id] = ""
        streamTasks[message.id] = Task { @MainActor [weak self] in
            var remaining = Substring(message.content)
            while !remaining.isEmpty {
                guard !Task.isCancelled else { return }
                let end = remaining.index(remaining.startIndex, offsetBy: Int.random(in: 2...6), limitedBy: remaining.endIndex) ?? remaining.endIndex
                let chunk = String(remaining[..<end])
                remaining = remaining[end...]
                self?.receiveChunk(chunk, for: message.id)
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            self?.streamTasks.removeValue(forKey: message.id)
            // Allow the final debounced render and layout to complete.
            self?.finalHeightRefreshes = 2
        }
        startHeightRefreshTimer()
    }

    private func receiveChunk(_ chunk: String, for messageID: UUID) {
        streamedContent[messageID, default: ""] += chunk
        guard let row = messages.firstIndex(where: { $0.id == messageID }),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? AssistantMessageCell else { return }
        cell.markdownView.appendMarkdownChunk(chunk)
    }

    private func scrollToLatestMessage() {
        let bottom = max(-tableView.adjustedContentInset.top,
                         tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom)
        tableView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    }

    private func resumeFollowingIfAtBottom() {
        let bottom = tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
        followsLatestMessage = bottom - tableView.contentOffset.y <= 24
    }

    private func send(_ text: String) {
        followsLatestMessage = true
        appendMessage(Message(id: UUID(), role: .user, content: text))

        let delayNanoseconds = UInt64.random(in: 400_000_000...900_000_000)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            let reply = buildMockAssistantReply(for: text)
            self.appendMessage(Message(id: UUID(), role: .assistant, content: reply))
        }
    }

    private func appendMessage(_ message: Message) {
        messages.append(message)
        if message.role == .assistant { startStreaming(message) }
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .none)
        if followsLatestMessage && !tableView.isTracking && !tableView.isDecelerating {
            tableView.layoutIfNeeded()
            scrollToLatestMessage()
        }
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
            cell.showContent(streamedContent[message.id] ?? "")
            return cell
        }
    }
}

extension MessageListViewController: UITableViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        followsLatestMessage = false
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { resumeFollowingIfAtBottom() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        resumeFollowingIfAtBottom()
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        followsLatestMessage = false
        return true
    }
}
