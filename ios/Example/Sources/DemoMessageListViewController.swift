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

class DemoMessageListViewController: DemoPageViewController {
    // Shared preset matching Android ALT_THEME.
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

    var currentTheme: THKMDTheme = DemoThemeStore.load()
    var interactionNotice: UILabel?

    func showInteractionNotice(_ message: String) {
        interactionNotice?.removeFromSuperview()
        let label = UILabel()
        label.text = message
        label.numberOfLines = 3
        label.textAlignment = .center
        label.font = .systemFont(ofSize: DemoUI.caption)
        label.textColor = DemoUI.surface
        label.backgroundColor = DemoUI.ink
        label.layer.cornerRadius = DemoUI.radius
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        interactionNotice = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: DemoUI.gutter),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -DemoUI.gutter),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: DemoUI.control)
        ])
        UIAccessibility.post(notification: .announcement, argument: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak label] in
            label?.removeFromSuperview()
            if self?.interactionNotice === label { self?.interactionNotice = nil }
        }
    }
    // Keep SSE progress independent of cell visibility and reuse.
    var streamedContent: [UUID: String] = [:]
    var playback: Task<Void, Never>?
    var followsLatestMessage = true
    var isScrollingToTop = false
    var finalHeightRefreshes = 0
    let tableView = UITableView(frame: .zero, style: .plain)

    var messages: [Message] = []

    var heightRefreshTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpTableView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme(DemoThemeStore.load())
        requestHeightRefresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        playback?.cancel(); playback = nil
        heightRefreshTimer?.invalidate(); heightRefreshTimer = nil
        interactionNotice?.removeFromSuperview()
    }

    // Apply saved settings to visible cells; reused cells read currentTheme.
    func applyTheme(_ theme: THKMDTheme) {
        currentTheme = theme
        DemoThemeStore.save(theme)
        for cell in tableView.visibleCells {
            (cell as? AssistantMessageCell)?.markdownView.theme = theme
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        heightRefreshTimer?.invalidate()
        playback?.cancel()
    }

    func setUpTableView() {
        tableView.register(AssistantMessageCell.self, forCellReuseIdentifier: AssistantMessageCell.reuseIdentifier)
        tableView.register(UserMessageCell.self, forCellReuseIdentifier: UserMessageCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.separatorStyle = .none
        tableView.backgroundColor = DemoUI.surface
        tableView.keyboardDismissMode = .interactive
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    // THKMDView grows via `invalidateIntrinsicContentSize()` as streamed chunks render, but
    // UITableView.automaticDimension only re-measures a row on its own layout passes — it
    // does not observe a child view's intrinsic size invalidation. While a row is streaming
    // in, nudge the table into re-measuring every tick so cells grow smoothly instead of
    // clipping/overlapping until the next unrelated layout pass. Restarted every time a new
    // assistant reply starts streaming, since that now happens repeatedly, not just once at
    // launch.
    func startHeightRefreshTimer() {
        guard heightRefreshTimer == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            // Don't fight a drag/deceleration with self-sizing row updates. The next
            // idle tick catches up using the message's latest streamed content.
            guard !self.tableView.isTracking, !self.tableView.isDragging,
                  !self.tableView.isDecelerating, !self.isScrollingToTop else { return }
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
            if self.playback == nil {
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

    func requestHeightRefresh() {
        finalHeightRefreshes = 2
        startHeightRefreshTimer()
    }

    func receiveChunk(_ chunk: String, for messageID: UUID) {
        streamedContent[messageID, default: ""] += chunk
        guard let row = messages.firstIndex(where: { $0.id == messageID }),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? AssistantMessageCell else { return }
        cell.markdownView.appendMarkdownChunk(chunk)
    }

    func scrollToLatestMessage() {
        let bottom = max(-tableView.adjustedContentInset.top,
                         tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom)
        tableView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    }

    func resumeFollowingIfAtBottom() {
        let bottom = tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
        followsLatestMessage = bottom - tableView.contentOffset.y <= 24
    }

    func appendMessage(_ message: Message) {
        messages.append(message)
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .none)
        if followsLatestMessage && !tableView.isTracking && !tableView.isDecelerating {
            tableView.layoutIfNeeded()
            scrollToLatestMessage()
        }
    }
}

extension DemoMessageListViewController: UITableViewDataSource {
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
            cell.markdownView.imageLoader = FixtureImageLoader()
            cell.markdownView.onContentSizeChange = { [weak self] in self?.requestHeightRefresh() }
            cell.markdownView.onLinkTap = { [weak self] url in self?.showInteractionNotice("链接：" + url.absoluteString); return false }
            cell.markdownView.onImageTap = { [weak self] url in self?.showInteractionNotice("图片：" + url.absoluteString); return false }
            cell.showContent(streamedContent[message.id] ?? message.content)
            return cell
        }
    }
}

extension DemoMessageListViewController: UITableViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isScrollingToTop = false
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
        // UIKit's status-bar scroll is animated but is neither a drag nor
        // deceleration. Offset restoration during that animation would cancel it.
        isScrollingToTop = true
        return true
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        isScrollingToTop = false
    }
}
