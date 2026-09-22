import UIKit

final class MessageListViewController: UITableViewController {
    private let markdownSamples = SampleMarkdown.all
    private var heightRefreshTimer: Timer?

    init() {
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "THKMDView Example"
        view.backgroundColor = .systemBackground
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.separatorStyle = .none
        startHeightRefreshTimer()
    }

    // THKMDView grows via `invalidateIntrinsicContentSize()` as streamed chunks render, but
    // UITableView.automaticDimension only re-measures a row on its own layout passes — it
    // does not observe a child view's intrinsic size invalidation. While rows are streaming
    // in, nudge the table into re-measuring every tick so cells grow smoothly instead of
    // clipping/overlapping until the next unrelated layout pass.
    private func startHeightRefreshTimer() {
        heightRefreshTimer?.invalidate()
        var ticksRemaining = 60 // ~9s, comfortably longer than the longest sample stream
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

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        markdownSamples.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseIdentifier, for: indexPath) as? MessageCell else {
            return UITableViewCell()
        }
        cell.startStreaming(markdownSamples[indexPath.row])
        return cell
    }
}
