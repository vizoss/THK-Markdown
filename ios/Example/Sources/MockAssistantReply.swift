import UIKit
import THKMDView

/// Example chrome only. Keep these tokens aligned with Android values/demo_ui.xml.
enum DemoUI {
    static let surface = UIColor(sampleHex: 0xFFFFFF) // Canvas and dialog surface.
    static let ink = UIColor(sampleHex: 0x202735) // Primary labels.
    static let muted = UIColor(sampleHex: 0x697386) // Progress and placeholders.
    static let accent = UIColor(sampleHex: 0x2563EB) // Primary action.
    static let soft = UIColor(sampleHex: 0xF1F5F9) // Flat secondary controls.
    static let border = UIColor(sampleHex: 0xE2E8F0) // Hairline separators.
    static let font: CGFloat = 14 // Control and dialog body size, sp/pt.
    static let caption: CGFloat = 12 // Progress label size.
    static let title: CGFloat = 18 // Header and dialog title size.
    static let gutter: CGFloat = 16 // Screen horizontal padding.
    static let control: CGFloat = 44 // Standard touch target height.
    static let radius: CGFloat = 8 // Control corner radius.
    static func style(_ button: UIButton, primary: Bool = false) {
        button.configuration = nil
        button.titleLabel?.font = .systemFont(ofSize: font, weight: .medium)
        button.setTitleColor(primary ? surface : ink, for: .normal)
        button.setTitleColor(muted, for: .disabled)
        button.backgroundColor = primary ? accent : soft
        button.layer.cornerRadius = radius
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    }
}

// Fixture content is provided by the MarkdownFixtures package product, never interpolated.
final class FixtureControls: UIStackView {
    var onSelect: (() -> Void)?
    var onNext: (() -> Void)?
    var onFull: (() -> Void)?
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStep: (() -> Void)?
    var onDetails: (() -> Void)?
    private let select = UIButton(type: .system)
    private let next = UIButton(type: .system)
    private let status = UIButton(type: .system)

    override init(frame: CGRect) { super.init(frame: frame); setUp() }
    required init(coder: NSCoder) { super.init(coder: coder); setUp() }

    private func setUp() {
        axis = .vertical
        spacing = 8
        DemoUI.style(select)
        select.titleLabel?.lineBreakMode = .byTruncatingTail
        select.heightAnchor.constraint(equalToConstant: DemoUI.control).isActive = true
        select.setTitle("选择 Markdown 用例", for: .normal)
        select.addTarget(self, action: #selector(selectTapped), for: .touchUpInside)
        let selection = UIStackView(arrangedSubviews: [select, next])
        selection.spacing = 8
        select.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        DemoUI.style(next)
        next.setTitle("下一条", for: .normal)
        next.isEnabled = false
        next.widthAnchor.constraint(equalToConstant: 76).isActive = true
        next.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        addArrangedSubview(selection)
        let actions = UIStackView()
        actions.distribution = .fillEqually
        actions.spacing = 8
        for (title, selector) in [("全文", #selector(fullTapped)), ("播放", #selector(playTapped)),
                                  ("暂停", #selector(pauseTapped)), ("单步", #selector(stepTapped))] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            DemoUI.style(button)
            button.addTarget(self, action: selector, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: DemoUI.control).isActive = true
            actions.addArrangedSubview(button)
        }
        addArrangedSubview(actions)
        setCustomSpacing(0, after: actions)
        status.titleLabel?.font = .systemFont(ofSize: DemoUI.caption)
        status.setTitleColor(DemoUI.muted, for: .normal)
        status.titleLabel?.textAlignment = .center
        status.heightAnchor.constraint(equalToConstant: 48).isActive = true
        status.titleLabel?.numberOfLines = 2
        status.addTarget(self, action: #selector(detailsTapped), for: .touchUpInside)
        addArrangedSubview(status)
    }
    func update(title: String, state: String, canGoNext: Bool = false) {
        next.isEnabled = canGoNext
        select.setTitle(title + " ▾", for: .normal)
        status.setTitle(state + " · 点击查看原文与验收要求", for: .normal)
    }
    @objc private func selectTapped() { onSelect?() }
    @objc private func nextTapped() { onNext?() }
    @objc private func fullTapped() { onFull?() }
    @objc private func playTapped() { onPlay?() }
    @objc private func pauseTapped() { onPause?() }
    @objc private func stepTapped() { onStep?() }
    @objc private func detailsTapped() { onDetails?() }
}

/// Scrollable flat modal shared visually with Android DemoDialog.
final class DemoDialogController: UIViewController {
    private let heading: String
    private let body: String?
    private let choices: [String]
    private let selected: Int
    private let onSelect: ((Int) -> Void)?

    init(title: String, body: String? = nil, choices: [String] = [], selected: Int = -1,
         onSelect: ((Int) -> Void)? = nil) {
        self.heading = title; self.body = body; self.choices = choices
        self.selected = selected; self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        let card = UIView()
        card.backgroundColor = DemoUI.surface
        card.layer.cornerRadius = 12
        card.accessibilityViewIsModal = true
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        let title = UILabel()
        title.text = heading
        title.font = .systemFont(ofSize: DemoUI.title, weight: .bold)
        title.textColor = DemoUI.ink
        title.numberOfLines = 2
        let close = UIButton(type: .system)
        DemoUI.style(close, primary: true)
        close.setTitle("关闭", for: .normal)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let content: UIView
        if let body {
            let text = UITextView()
            text.isEditable = false
            text.backgroundColor = .clear
            text.textContainerInset = .zero
            text.textContainer.lineFragmentPadding = 0
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            text.attributedText = NSAttributedString(string: body, attributes: [
                .font: UIFont.systemFont(ofSize: DemoUI.font), .foregroundColor: DemoUI.ink,
                .paragraphStyle: paragraph
            ])
            content = text
        } else {
            let scroll = UIScrollView()
            let rows = UIStackView()
            rows.axis = .vertical
            rows.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(rows)
            for (index, label) in choices.enumerated() {
                let button = UIButton(type: .system)
                DemoUI.style(button)
                button.backgroundColor = index == selected ? DemoUI.soft : DemoUI.surface
                button.setTitleColor(index == selected ? DemoUI.accent : DemoUI.ink, for: .normal)
                button.contentHorizontalAlignment = .left
                button.titleLabel?.numberOfLines = 2
                button.setTitle((index == selected ? "✓  " : "") + label, for: .normal)
                button.tag = index
                button.addTarget(self, action: #selector(choiceTapped(_:)), for: .touchUpInside)
                button.heightAnchor.constraint(equalToConstant: 48).isActive = true
                rows.addArrangedSubview(button)
            }
            NSLayoutConstraint.activate([
                rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
            ])
            content = scroll
        }
        for child in [title, content, close] {
            child.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(child)
        }
        let width = card.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            width, card.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            card.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.7),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -16),
            close.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            close.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            close.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            close.heightAnchor.constraint(equalToConstant: DemoUI.control)
        ])
        title.setContentCompressionResistancePriority(.required, for: .vertical)
        title.setContentHuggingPriority(.required, for: .vertical)
    }
    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func choiceTapped(_ sender: UIButton) {
        let index = sender.tag
        let handler = onSelect
        dismiss(animated: true) { handler?(index) }
    }
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
