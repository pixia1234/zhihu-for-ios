import UIKit

final class MessagesViewController: UIViewController {
    private let categoryControl = UISegmentedControl(items: ZhihuNotificationCategory.allCases.map(\.title))
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var items = SampleData.messages
    private var category: ZhihuNotificationCategory = .comments

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "消息"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "checkmark.circle"), style: .plain, target: self, action: #selector(markRead))
        categoryControl.selectedSegmentIndex = 0
        categoryControl.selectedSegmentTintColor = AppTheme.zhihuBlue
        categoryControl.setTitleTextAttributes([.foregroundColor: AppTheme.secondaryText], for: .normal)
        categoryControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        categoryControl.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
        categoryControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(categoryControl)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseIdentifier)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            categoryControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            categoryControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            categoryControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            categoryControl.heightAnchor.constraint(equalToConstant: 32),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        loadRemoteMessages()
    }

    @objc private func categoryChanged() {
        category = ZhihuNotificationCategory.allCases[categoryControl.selectedSegmentIndex]
        loadRemoteMessages()
    }

    private func loadRemoteMessages() {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
            items = SampleData.messages
            tableView.reloadData()
            return
        }
        RemoteNotificationRepository.shared.fetch(category: category) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(remote):
                self.items = remote.map {
                    MessageItem(title: $0.authorName ?? $0.title, detail: $0.detail.isEmpty ? $0.title : $0.detail, date: $0.date, symbol: self.category.symbol, color: AppTheme.zhihuBlue, id: $0.id, avatarURL: $0.avatarURL, isRead: $0.isRead, destinationURL: $0.destinationURL)
                }
                self.tableView.reloadData()
                self.updateEmptyState()
            case let .failure(error):
                self.items = []
                self.tableView.reloadData()
                self.showError(error)
            }
        }
    }

    @objc private func markRead() {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else { return }
        RemoteNotificationRepository.shared.markAsRead(category: category) { [weak self] result in
            guard let self = self else { return }
            if case .success = result {
                self.items = self.items.map { MessageItem(title: $0.title, detail: $0.detail, date: $0.date, symbol: $0.symbol, color: $0.color, id: $0.id, avatarURL: $0.avatarURL, isRead: true, destinationURL: $0.destinationURL) }
                self.tableView.reloadData()
            }
        }
    }

    private func updateEmptyState() {
        guard items.isEmpty else { tableView.backgroundView = nil; return }
        let label = UILabel()
        label.text = "当前分类暂无消息"
        label.textColor = AppTheme.secondaryText
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15)
        tableView.backgroundView = label
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "消息加载失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        present(alert, animated: true)
    }
}

final class MessageCell: UITableViewCell {
    static let reuseIdentifier = "MessageCell"
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        let iconContainer = UIView()
        iconContainer.layer.cornerRadius = 21
        iconContainer.clipsToBounds = true
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFill
        iconView.tintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 42), iconContainer.heightAnchor.constraint(equalToConstant: 42),
            iconView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor), iconView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: iconContainer.topAnchor), iconView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor)
        ])

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 4
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = AppTheme.secondaryText
        detailLabel.numberOfLines = 3
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = AppTheme.secondaryText
        let row = UIStackView(arrangedSubviews: [iconContainer, labels, dateLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor), row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        iconView.tintColor = .white
    }

    func configure(with item: MessageItem) {
        iconView.image = UIImage(systemName: item.symbol)
        iconView.tintColor = .white
        iconView.backgroundColor = item.color
        titleLabel.text = item.isRead ? item.title : "●  (item.title)"
        titleLabel.textColor = item.isRead ? AppTheme.text : AppTheme.zhihuBlue
        detailLabel.text = item.detail
        dateLabel.text = item.date
        if let url = item.avatarURL {
            ImagePipeline.shared.image(for: url) { [weak self] image in
                guard let self = self, let image = image else { return }
                self.iconView.image = image
                self.iconView.tintColor = nil
                self.iconView.backgroundColor = .clear
            }
        }
    }
}

extension MessagesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseIdentifier, for: indexPath) as! MessageCell
        cell.configure(with: items[indexPath.row])
        return cell
    }
}

extension MessagesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let url = items[indexPath.row].destinationURL else { return }
        navigationController?.pushViewController(WebContentViewController(url: url, title: "知乎消息"), animated: true)
    }
}
