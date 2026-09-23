import UIKit
import THKMDView
import MarkdownFixtures

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

    private var currentTheme: THKMDTheme = DemoThemeStore.load()
    // Keep SSE progress independent of cell visibility and reuse.
    private var streamedContent: [UUID: String] = [:]
    private var playback: Task<Void, Never>?
    private var fixtures: [MarkdownFixture] = []
    private var selectedFixture = 0
    private var playbackMessageID: UUID?
    private var chunkIndex = 0
    private let fixtureControls = FixtureControls()
    private var followsLatestMessage = true
    private var isScrollingToTop = false
    private var finalHeightRefreshes = 0
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = MessageInputBar()
    private let demoHeader = UIView()
    private var inputBarBottomConstraint: NSLayoutConstraint!

    private var messages: [Message] = []

    private var heightRefreshTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "THKMDView Demo"
        overrideUserInterfaceStyle = .light
        view.backgroundColor = DemoUI.surface
        navigationController?.setNavigationBarHidden(true, animated: false)
        setUpHeader()

        setUpTableView()
        setUpFixtureControls()
        setUpInputBar()
        setUpKeyboardObservers()
        setUpDismissKeyboardOnTap()
        do {
fixtures = try MarkdownFixture.loadAll()
            showFixture(full: true)
        } catch {
            fixtureControls.update(title: "用例加载失败", state: error.localizedDescription)
        }
    }

    private func setUpHeader() {
        demoHeader.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(demoHeader)
        let title = UILabel()
        title.text = "THKMDView Demo"
        title.font = .systemFont(ofSize: DemoUI.title, weight: .bold)
        title.textColor = DemoUI.ink
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        demoHeader.addSubview(title)
        let theme = UIButton(type: .system)
        DemoUI.style(theme)
        theme.backgroundColor = .clear
        theme.setTitleColor(DemoUI.accent, for: .normal)
        theme.setTitle("主题", for: .normal)
        theme.addTarget(self, action: #selector(openThemeSettings), for: .touchUpInside)
        theme.translatesAutoresizingMaskIntoConstraints = false
        demoHeader.addSubview(theme)
        NSLayoutConstraint.activate([
            demoHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            demoHeader.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            demoHeader.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            demoHeader.heightAnchor.constraint(equalToConstant: 56),
            title.centerXAnchor.constraint(equalTo: demoHeader.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: demoHeader.centerYAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: demoHeader.leadingAnchor, constant: 80),
            title.trailingAnchor.constraint(lessThanOrEqualTo: demoHeader.trailingAnchor, constant: -80),
            theme.trailingAnchor.constraint(equalTo: demoHeader.trailingAnchor, constant: -DemoUI.gutter),
            theme.centerYAnchor.constraint(equalTo: demoHeader.centerYAnchor),
            theme.widthAnchor.constraint(equalToConstant: 60),
            theme.heightAnchor.constraint(equalToConstant: DemoUI.control)
        ])
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

    private func setUpTableView() {
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

    private func setUpInputBar() {
        inputBar.onSend = { [weak self] text in
            self?.send(text)
        }
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)

        inputBarBottomConstraint = inputBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: fixtureControls.bottomAnchor),
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

    private func setUpFixtureControls() {
        fixtureControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fixtureControls)
        NSLayoutConstraint.activate([
            fixtureControls.topAnchor.constraint(equalTo: demoHeader.bottomAnchor, constant: 8),
            fixtureControls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: DemoUI.gutter),
            fixtureControls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -DemoUI.gutter)
        ])
        fixtureControls.onSelect = { [weak self] in self?.selectFixture() }
        fixtureControls.onPrevious = { [weak self] in
            guard let self, let previous = self.previousFixtureIndex() else { return }
            self.selectedFixture = previous
            self.showFixture(full: true)
        }
        fixtureControls.onNext = { [weak self] in
            guard let self, let next = self.nextFixtureIndex() else { return }
            self.selectedFixture = next
            self.showFixture(full: true)
        }
        fixtureControls.onFull = { [weak self] in self?.showFixture(full: true) }
        fixtureControls.onPlay = { [weak self] in self?.playFixture() }
        fixtureControls.onPause = { [weak self] in
            self?.playback?.cancel(); self?.playback = nil
            self?.updateFixtureStatus("已暂停")
        }
        fixtureControls.onStep = { [weak self] in
            guard let self, !self.fixtures.isEmpty else { return }
            self.playback?.cancel(); self.playback = nil
            if self.chunkIndex >= self.fixtures[self.selectedFixture].chunks.count { self.showFixture(full: false) }
            self.advanceFixture()
        }
        fixtureControls.onDetails = { [weak self] in
            guard let self, !self.fixtures.isEmpty else { return }
            let fixture = self.fixtures[self.selectedFixture]
            let alert = DemoDialogController(title: fixture.id + " · " + fixture.title,
                body: "验收要求\n" + fixture.summary + "\n\nMarkdown 原文\n" + fixture.markdown)
            self.present(alert, animated: true)
        }
    }

    private func selectFixture() {
        let groups = ["P0", "P1"]
        let currentID = fixtures.indices.contains(selectedFixture) ? fixtures[selectedFixture].id : ""
        let labels = groups.map { group in
            "\(group) · \(fixtures.filter { $0.id.hasPrefix(group + "-") }.count) 个用例  ›"
        }
        let sheet = DemoDialogController(title: "Markdown 用例", choices: labels,
            selected: groups.firstIndex { currentID.hasPrefix($0 + "-") } ?? -1) { [weak self] index in
            self?.selectFixture(in: groups[index])
        }
        present(sheet, animated: true)
    }

    private func selectFixture(in group: String) {
        // Preserve catalog indices when displaying only one suite.
        let indices = fixtures.indices.filter { fixtures[$0].id.hasPrefix(group + "-") }
        let labels = ["‹ 返回 P0 / P1"] + indices.map { fixtures[$0].id + " · " + fixtures[$0].title }
        let selected = indices.firstIndex(of: selectedFixture).map { $0 + 1 } ?? -1
        let sheet = DemoDialogController(title: group + " 用例", choices: labels,
            selected: selected) { [weak self] row in
            guard let self else { return }
            if row == 0 {
                self.selectFixture()
            } else {
                self.selectedFixture = indices[row - 1]
                self.showFixture(full: true)
            }
        }
        present(sheet, animated: true)
    }

    private func showFixture(full: Bool, clearHistory: Bool = true) {
        guard !fixtures.isEmpty else { return }
        playback?.cancel(); playback = nil
        heightRefreshTimer?.invalidate(); heightRefreshTimer = nil
        let fixture = fixtures[selectedFixture]
        if clearHistory {
            messages = fixture.history.map { Message(id: UUID(), role: .assistant, content: $0) }
            streamedContent.removeAll()
        }
        let message = Message(id: UUID(), role: .assistant, content: fixture.markdown)
        playbackMessageID = message.id
        chunkIndex = full ? fixture.chunks.count : 0
        streamedContent[message.id] = full ? fixture.markdown : ""
        messages.append(message)
        followsLatestMessage = true
        isScrollingToTop = false
        tableView.reloadData()
        tableView.layoutIfNeeded()
        scrollToLatestMessage()
        updateFixtureStatus(full ? "全文" : "待播放")
        requestHeightRefresh()
    }

    private func playFixture() {
        guard !fixtures.isEmpty else { return }
        playback?.cancel()
        if chunkIndex >= fixtures[selectedFixture].chunks.count { showFixture(full: false) }
        playback = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.hasRemainingChunks == true else { break }
                self?.advanceFixture()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.playback = nil
            self?.updateFixtureStatus("已完成")
            self?.requestHeightRefresh()
        }
        requestHeightRefresh()
    }

    private func advanceFixture() {
        guard let id = playbackMessageID, !fixtures.isEmpty else { return }
        let chunks = fixtures[selectedFixture].chunks
        guard chunkIndex < chunks.count else { return }
        receiveChunk(chunks[chunkIndex], for: id)
        chunkIndex += 1
        updateFixtureStatus(chunkIndex == chunks.count ? "已完成" : "逐步渲染")
        requestHeightRefresh()
    }

    private var hasRemainingChunks: Bool {
        !fixtures.isEmpty && chunkIndex < fixtures[selectedFixture].chunks.count
    }

    private func previousFixtureIndex() -> Int? {
        guard fixtures.indices.contains(selectedFixture),
              let group = fixtures[selectedFixture].id.split(separator: "-").first else { return nil }
        return fixtures.indices.last { $0 < selectedFixture && fixtures[$0].id.hasPrefix(String(group) + "-") }
    }

    private func nextFixtureIndex() -> Int? {
        guard fixtures.indices.contains(selectedFixture),
              let group = fixtures[selectedFixture].id.split(separator: "-").first else { return nil }
        return fixtures.indices.first { $0 > selectedFixture && fixtures[$0].id.hasPrefix(String(group) + "-") }
    }

    private func updateFixtureStatus(_ state: String) {
        guard !fixtures.isEmpty else { return }
        let fixture = fixtures[selectedFixture]
        fixtureControls.update(title: fixture.id + " · " + fixture.title,
                               state: "\(state) · \(chunkIndex)/\(fixture.chunks.count) 分片",
                               canGoNext: nextFixtureIndex() != nil,
                               canGoPrevious: previousFixtureIndex() != nil)
    }

    private func requestHeightRefresh() {
        finalHeightRefreshes = 2
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

        showFixture(full: false, clearHistory: false)
        playFixture()
    }

    private func appendMessage(_ message: Message) {
        messages.append(message)
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
            cell.markdownView.imageLoader = FixtureImageLoader()
            cell.markdownView.onContentSizeChange = { [weak self] in self?.requestHeightRefresh() }
            cell.markdownView.onLinkTap = { [weak self] url in self?.updateFixtureStatus("链接：" + url.absoluteString); return true }
            cell.markdownView.onImageTap = { [weak self] url in self?.updateFixtureStatus("图片：" + url.absoluteString); return true }
            cell.showContent(streamedContent[message.id] ?? message.content)
            return cell
        }
    }
}

extension MessageListViewController: UITableViewDelegate {
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
