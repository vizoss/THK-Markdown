import UIKit
import MarkdownFixtures

final class ShowCaseViewController: DemoMessageListViewController {
    override var pageTitle: String { "ShowCase 格式显示" }
    private var fixtures: [MarkdownFixture] = []
    private var selectedFixture = 0
    private var playbackMessageID: UUID?
    private var chunkIndex = 0
    private let fixtureControls = FixtureControls()

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpFixtureControls()
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: fixtureControls.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        do {
            fixtures = try MarkdownFixture.loadAll()
            showFixture(full: true)
        } catch {
            fixtureControls.update(title: "用例加载失败", state: error.localizedDescription)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if hasRemainingChunks { updateFixtureStatus("已暂停") }
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
        let groups = ["P0", "P1", "P2", "P3"]
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
        let labels = ["‹ 返回分组"] + indices.map { fixtures[$0].id + " · " + fixtures[$0].title }
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

    private func showFixture(full: Bool) {
        guard !fixtures.isEmpty else { return }
        playback?.cancel(); playback = nil
        heightRefreshTimer?.invalidate(); heightRefreshTimer = nil
        let fixture = fixtures[selectedFixture]
        messages = fixture.history.map { Message(id: UUID(), role: .assistant, content: $0) }
        streamedContent.removeAll()
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
        guard fixtures.indices.contains(selectedFixture), selectedFixture > 0 else { return nil }
        return selectedFixture - 1
    }

    private func nextFixtureIndex() -> Int? {
        guard fixtures.indices.contains(selectedFixture), selectedFixture + 1 < fixtures.count else { return nil }
        return selectedFixture + 1
    }

    private func updateFixtureStatus(_ state: String) {
        guard !fixtures.isEmpty else { return }
        let fixture = fixtures[selectedFixture]
        fixtureControls.update(title: fixture.id + " · " + fixture.title,
                               state: "\(state) · \(chunkIndex)/\(fixture.chunks.count) 分片",
                               canGoNext: nextFixtureIndex() != nil,
                               canGoPrevious: previousFixtureIndex() != nil)
    }


}
