import UIKit

final class MainViewController: DemoPageViewController {
    override var showsBack: Bool { false }
    override var showsTheme: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let entries: [(String, () -> UIViewController)] = [
            ("ShowCase 格式显示", { ShowCaseViewController() }),
            ("SSE Chat", { SSEChatViewController() }),
            ("科技周刊 · 50 篇", { WeeklyListViewController() }),
            ("主题设置", { ThemeSettingsViewController() })
        ]
        for (title, destination) in entries {
            let button = UIButton(type: .system)
            DemoUI.style(button)
            button.setTitle(title + "  ›", for: .normal)
            button.heightAnchor.constraint(equalToConstant: 64).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.navigationController?.pushViewController(destination(), animated: true)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: demoHeader.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DemoUI.gutter),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: DemoUI.gutter),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -DemoUI.gutter),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DemoUI.gutter),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -2 * DemoUI.gutter)
        ])
    }
}
