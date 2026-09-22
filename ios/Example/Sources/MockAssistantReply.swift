import UIKit
import THKMDView

// Fixture content is provided by the MarkdownFixtures package product, never interpolated.
final class FixtureControls: UIStackView {
    var onSelect: (() -> Void)?
    var onFull: (() -> Void)?
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStep: (() -> Void)?
    var onDetails: (() -> Void)?
    private let select = UIButton(type: .system)
    private let status = UIButton(type: .system)

    override init(frame: CGRect) { super.init(frame: frame); setUp() }
    required init(coder: NSCoder) { super.init(coder: coder); setUp() }

    private func setUp() {
        axis = .vertical
        spacing = 4
        select.setTitle("选择 P0 用例", for: .normal)
        select.addTarget(self, action: #selector(selectTapped), for: .touchUpInside)
        addArrangedSubview(select)
        let actions = UIStackView()
        actions.distribution = .fillEqually
        for (title, selector) in [("全文", #selector(fullTapped)), ("播放", #selector(playTapped)),
                                  ("暂停", #selector(pauseTapped)), ("单步", #selector(stepTapped))] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.addTarget(self, action: selector, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            actions.addArrangedSubview(button)
        }
        addArrangedSubview(actions)
        status.titleLabel?.font = .systemFont(ofSize: 12)
        status.titleLabel?.numberOfLines = 2
        status.addTarget(self, action: #selector(detailsTapped), for: .touchUpInside)
        addArrangedSubview(status)
    }
    func update(title: String, state: String) {
        select.setTitle(title + " ▾", for: .normal)
        status.setTitle(state + " · 点击查看原文与验收要求", for: .normal)
    }
    @objc private func selectTapped() { onSelect?() }
    @objc private func fullTapped() { onFull?() }
    @objc private func playTapped() { onPlay?() }
    @objc private func pauseTapped() { onPause?() }
    @objc private func stepTapped() { onStep?() }
    @objc private func detailsTapped() { onDetails?() }
}

struct FixtureImageLoader: THKImageLoading {
    func load(url: URL) async -> UIImage? {
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled, url.absoluteString == "https://fixtures.thk.invalid/ok.png" else { return nil }
        return await MainActor.run {
            UIGraphicsImageRenderer(size: CGSize(width: 120, height: 64)).image { context in
                UIColor(red: 10 / 255.0, green: 132 / 255.0, blue: 1, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 64))
            }
        }
    }
}
