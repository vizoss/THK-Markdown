import UIKit

/// One flat 56pt header across the home page and all pushed destinations.
class DemoPageViewController: UIViewController {
    var pageTitle: String { "THKMDView Demo" }
    var showsBack: Bool { true }
    var showsTheme: Bool { true }
    let demoHeader = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = DemoUI.surface
        navigationController?.setNavigationBarHidden(true, animated: false)
        demoHeader.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(demoHeader)
        let label = UILabel()
        label.text = pageTitle
        label.font = .systemFont(ofSize: DemoUI.title, weight: .bold)
        label.textColor = DemoUI.ink
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        label.translatesAutoresizingMaskIntoConstraints = false
        demoHeader.addSubview(label)
        let back = UIButton(type: .system)
        let theme = UIButton(type: .system)
        for button in [back, theme] {
            DemoUI.style(button)
            button.backgroundColor = .clear
            button.setTitleColor(DemoUI.accent, for: .normal)
            button.translatesAutoresizingMaskIntoConstraints = false
            demoHeader.addSubview(button)
        }
        back.setTitle("‹ 返回", for: .normal)
        back.isHidden = !showsBack
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        theme.setTitle("主题", for: .normal)
        theme.isHidden = !showsTheme
        theme.addAction(UIAction { [weak self] _ in self?.navigationController?.pushViewController(ThemeSettingsViewController(), animated: true) }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            demoHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            demoHeader.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            demoHeader.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            demoHeader.heightAnchor.constraint(equalToConstant: 56),
            label.centerYAnchor.constraint(equalTo: demoHeader.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: demoHeader.leadingAnchor, constant: 80),
            label.trailingAnchor.constraint(equalTo: demoHeader.trailingAnchor, constant: -80),
            back.leadingAnchor.constraint(equalTo: demoHeader.leadingAnchor, constant: DemoUI.gutter),
            back.centerYAnchor.constraint(equalTo: demoHeader.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 60), back.heightAnchor.constraint(equalToConstant: DemoUI.control),
            theme.trailingAnchor.constraint(equalTo: demoHeader.trailingAnchor, constant: -DemoUI.gutter),
            theme.centerYAnchor.constraint(equalTo: demoHeader.centerYAnchor),
            theme.widthAnchor.constraint(equalToConstant: 60), theme.heightAnchor.constraint(equalToConstant: DemoUI.control)
        ])
    }
}
