import UIKit
import THKMDView

/// A modal settings sheet exposing every `THKMDTheme` property as a live-editable control —
/// colors via `UIColorWell`, sizes via `UISlider` — mirroring a parallel
/// `BottomSheetDialogFragment` feature on Android this round. Every control change rebuilds a
/// full `THKMDTheme` from all current control values and reports it through `onThemeChange`,
/// which `MessageListViewController` wires to the same "push a new theme onto currently-bound
/// cells" path the old toggle-theme button used (`THKMDView.theme = ...`, no `setMarkdown`
/// call needed).
final class ThemeSettingsViewController: UIViewController {
    var onThemeChange: ((THKMDTheme) -> Void)?

    private var theme: THKMDTheme
    private let presets: [(name: String, theme: THKMDTheme)]

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    // Each row keeps both a getter and setter closure (not just a setter) so a preset
    // quick-select can pull that row's new value back out of the preset theme and push it
    // into the control, in addition to a manual edit pushing the control's value into `theme`.
    private var colorRows: [(well: UIColorWell, get: (THKMDTheme) -> UIColor, set: (inout THKMDTheme, UIColor) -> Void)] = []
    private var sliderRows: [(slider: UISlider, valueLabel: UILabel, get: (THKMDTheme) -> Float, set: (inout THKMDTheme, Float) -> Void)] = []

    init(theme: THKMDTheme, presets: [(name: String, theme: THKMDTheme)]) {
        self.theme = theme
        self.presets = presets
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Theme Settings"
        view.backgroundColor = .systemBackground

        setUpScrollView()
        addPresetRow()
        addSectionLabel("Colors")
        addColorRows()
        addSectionLabel("Sizes")
        addSizeRows()
    }

    private func setUpScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            // Pins the stack's width to the scroll view's frame (not its content), which is
            // what makes a UIScrollView scroll only vertically here.
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }

    private func addSectionLabel(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        stack.addArrangedSubview(label)
    }

    // Quick-select presets populate every control at once; fine-grained manual control
    // (below) stays available afterward.
    private func addPresetRow() {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        for preset in presets {
            var configuration = UIButton.Configuration.plain()
            configuration.title = preset.name
            configuration.baseBackgroundColor = .secondarySystemBackground
            configuration.background.backgroundColor = .secondarySystemBackground
            configuration.background.cornerRadius = 8
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { [weak self] _ in
                self?.applyPreset(preset.theme)
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        stack.addArrangedSubview(row)
    }

    private func applyPreset(_ newTheme: THKMDTheme) {
        theme = newTheme
        for row in colorRows {
            row.well.selectedColor = row.get(newTheme)
        }
        for row in sliderRows {
            let value = row.get(newTheme)
            row.slider.value = value
            row.valueLabel.text = Self.formatValue(value)
        }
        onThemeChange?(theme)
    }

    private func addColorRows() {
        addColorRow(title: "Body Text", get: { $0.bodyTextColor }, set: { $0.bodyTextColor = $1 })
        addColorRow(title: "Heading Text", get: { $0.headingTextColor }, set: { $0.headingTextColor = $1 })
        addColorRow(title: "Link", get: { $0.linkColor }, set: { $0.linkColor = $1 })
        addColorRow(title: "Code Text", get: { $0.codeTextColor }, set: { $0.codeTextColor = $1 })
        addColorRow(title: "Code Background", get: { $0.codeBackgroundColor }, set: { $0.codeBackgroundColor = $1 })
        addColorRow(title: "Quote Bar", get: { $0.blockQuoteBarColor }, set: { $0.blockQuoteBarColor = $1 })
        addColorRow(title: "Quote Text", get: { $0.blockQuoteTextColor }, set: { $0.blockQuoteTextColor = $1 })
        addColorRow(title: "Quote Background", get: { $0.blockQuoteBackgroundColor }, set: { $0.blockQuoteBackgroundColor = $1 })
        addColorRow(title: "Table Border", get: { $0.tableBorderColor }, set: { $0.tableBorderColor = $1 })
        addColorRow(title: "Table Header Background", get: { $0.tableHeaderBackgroundColor }, set: { $0.tableHeaderBackgroundColor = $1 })
        addColorRow(title: "View Background", get: { $0.backgroundColor }, set: { $0.backgroundColor = $1 })
    }

    private func addSizeRows() {
        addSliderRow(
            title: "Code Corner Radius", min: 0, max: 20,
            get: { Float($0.codeBlockCornerRadius) }, set: { $0.codeBlockCornerRadius = CGFloat($1) }
        )
        addSliderRow(
            title: "Body Font Size", min: 10, max: 24,
            get: { Float($0.bodyFontSize) }, set: { $0.bodyFontSize = CGFloat($1) }
        )
        addSliderRow(
            title: "Code Font Size", min: 10, max: 24,
            get: { Float($0.codeFontSize) }, set: { $0.codeFontSize = CGFloat($1) }
        )
    }

    private func addColorRow(
        title: String,
        get: @escaping (THKMDTheme) -> UIColor,
        set: @escaping (inout THKMDTheme, UIColor) -> Void
    ) {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12

        let label = UILabel()
        label.text = title
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let well = UIColorWell()
        well.selectedColor = get(theme)
        well.setContentHuggingPriority(.required, for: .horizontal)
        well.addTarget(self, action: #selector(colorWellChanged(_:)), for: .valueChanged)

        row.addArrangedSubview(label)
        row.addArrangedSubview(well)
        stack.addArrangedSubview(row)

        colorRows.append((well, get, set))
    }

    private func addSliderRow(
        title: String,
        min: Float,
        max: Float,
        get: @escaping (THKMDTheme) -> Float,
        set: @escaping (inout THKMDTheme, Float) -> Void
    ) {
        let row = UIStackView()
        row.axis = .vertical
        row.spacing = 4

        let header = UIStackView()
        header.axis = .horizontal

        let titleLabel = UILabel()
        titleLabel.text = title

        let initial = get(theme)
        let valueLabel = UILabel()
        valueLabel.text = Self.formatValue(initial)
        valueLabel.textAlignment = .right
        valueLabel.textColor = .secondaryLabel

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(valueLabel)

        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = initial
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)

        row.addArrangedSubview(header)
        row.addArrangedSubview(slider)
        stack.addArrangedSubview(row)

        sliderRows.append((slider, valueLabel, get, set))
    }

    private static func formatValue(_ value: Float) -> String {
        String(format: "%.1f", value)
    }

    @objc private func colorWellChanged(_ sender: UIColorWell) {
        guard let row = colorRows.first(where: { $0.well === sender }) else { return }
        row.set(&theme, sender.selectedColor ?? .clear)
        onThemeChange?(theme)
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        guard let row = sliderRows.first(where: { $0.slider === sender }) else { return }
        row.valueLabel.text = Self.formatValue(sender.value)
        row.set(&theme, sender.value)
        onThemeChange?(theme)
    }
}
