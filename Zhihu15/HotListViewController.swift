import UIKit

final class HotListViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "热榜"
        view.backgroundColor = .systemGroupedBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.register(HotCell.self, forCellReuseIdentifier: HotCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

final class HotCell: UITableViewCell {
    static let reuseIdentifier = "HotCell"
    private let rankLabel = UILabel()
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let metaLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AppTheme.card
        selectionStyle = .default
        let stack = UIStackView(arrangedSubviews: [rankLabel, titleLabel, summaryLabel, metaLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        rankLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        rankLabel.textColor = AppTheme.zhihuBlue
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.numberOfLines = 0
        summaryLabel.font = .systemFont(ofSize: 14)
        summaryLabel.textColor = AppTheme.secondaryText
        summaryLabel.numberOfLines = 2
        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = AppTheme.secondaryText
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with item: HotItem) {
        rankLabel.text = String(format: "%02d  %@", item.rank, item.category)
        titleLabel.text = item.title
        summaryLabel.text = item.summary
        metaLabel.text = item.heat
    }
}

extension HotListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { SampleData.hot.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: HotCell.reuseIdentifier, for: indexPath) as! HotCell
        cell.configure(with: SampleData.hot[indexPath.row])
        return cell
    }
}

extension HotListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let hot = SampleData.hot[indexPath.row]
        let item = FeedItem(id: 1000 + hot.rank, kind: .question, author: "知乎热榜", authorRole: hot.category + " · " + hot.heat, avatarColor: .systemOrange, title: hot.title, excerpt: hot.summary, topic: hot.category, upvotes: 0, comments: 0, hasImage: false, imageColor: .clear)
        navigationController?.pushViewController(DetailViewController(item: item), animated: true)
    }
}
