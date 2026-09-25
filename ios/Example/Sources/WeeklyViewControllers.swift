import UIKit
import THKMDView

private struct WeeklyArticle: Decodable {
    let number: Int
    let title: String
    let path: String
    var sourceURL: URL { URL(string: "https://github.com/ruanyf/weekly/blob/master/\(path)")! }
    var rawURL: URL { URL(string: "https://raw.githubusercontent.com/ruanyf/weekly/master/\(path)")! }
    static func load() throws -> [WeeklyArticle] {
        guard let url = Bundle.main.url(forResource: "weekly", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([WeeklyArticle].self, from: Data(contentsOf: url))
    }
}

private final class WeeklyCell: UITableViewCell {
    let label = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        let card = UIView()
        card.backgroundColor = DemoUI.soft; card.layer.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        label.numberOfLines = 0; label.font = .systemFont(ofSize: 16); label.textColor = DemoUI.ink
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class WeeklyListViewController: DemoPageViewController, UITableViewDataSource, UITableViewDelegate {
    override var pageTitle: String { "科技周刊" }
    private var articles: [WeeklyArticle] = []
    override func viewDidLoad() {
        super.viewDidLoad()
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self; table.delegate = self
        table.separatorStyle = .none
        table.backgroundColor = DemoUI.surface
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 76
        table.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        let header = UILabel(frame: CGRect(x: 0, y: 0, width: 300, height: 72))
        header.numberOfLines = 0; header.font = .systemFont(ofSize: 13)
        header.textColor = .secondaryLabel
        do {
            articles = try WeeklyArticle.load()
            header.text = "阮一峰 · 科技爱好者周刊\n50 篇 · 第 364–413 期 · 在线阅读"
        } catch { header.text = "文章目录读取失败" }
        table.tableHeaderView = header
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: demoHeader.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            table.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { articles.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "weekly") as? WeeklyCell ?? WeeklyCell(style: .default, reuseIdentifier: "weekly")
        let article = articles[indexPath.row]
        cell.label.text = "第 \(article.number) 期  ›\n\(article.title)"
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(WeeklyDetailViewController(article: articles[indexPath.row]), animated: true)
    }
}

private final class WeeklyDetailViewController: DemoPageViewController {
    private let article: WeeklyArticle
    override var pageTitle: String { "第 \(article.number) 期" }
    private let markdown = THKMDView()
    private let status = UIButton(type: .system)
    private var request: URLSessionDataTask?
    init(article: WeeklyArticle) { self.article = article; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { request?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let source = UIButton(type: .system)
        DemoUI.style(source)
        source.setTitle("阮一峰 · 科技爱好者周刊 · 查看原文 ↗", for: .normal)
        source.titleLabel?.font = .systemFont(ofSize: 13)
        source.titleLabel?.numberOfLines = 0
        source.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        source.addAction(UIAction { [weak self] _ in
            guard let self else { return }; self.open(self.article.sourceURL)
        }, for: .touchUpInside)
        DemoUI.style(status)
        status.titleLabel?.numberOfLines = 0
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        status.addAction(UIAction { [weak self] _ in self?.loadArticle() }, for: .touchUpInside)
        markdown.onLinkTap = { [weak self] url in
            guard let self else { return false }
            self.open(URL(string: url.relativeString, relativeTo: self.article.sourceURL)?.absoluteURL ?? url)
            return false
        }
        markdown.onContentSizeChange = { [weak self] in self?.view.setNeedsLayout() }
        for child in [source, status, markdown] { stack.addArrangedSubview(child) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: demoHeader.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        loadArticle()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        markdown.theme = DemoThemeStore.load()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController == nil { request?.cancel(); markdown.reset() }
    }
    private func open(_ url: URL) {
        guard ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
        UIApplication.shared.open(url)
    }
    private func loadArticle() {
        request?.cancel()
        status.isHidden = false; status.isEnabled = false
        status.setTitle("正在加载…", for: .normal)
        var urlRequest = URLRequest(url: article.rawURL)
        urlRequest.timeoutInterval = 30
        request = URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            if (error as? URLError)?.code == .cancelled { return }
            let content: String?
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
               let data, data.count <= 2_000_000, let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { content = text }
            else { content = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let content {
                    self.markdown.setMarkdown(content)
                    self.status.isHidden = true
                } else {
                    self.status.setTitle("加载失败，请检查网络 · 点击重试", for: .normal)
                    self.status.isEnabled = true
                }
            }
        }
        request?.resume()
    }
}
