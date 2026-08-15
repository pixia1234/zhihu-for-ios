import UIKit

final class CollectionsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items = Array(SampleData.recommendations.prefix(3))

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "收藏"
        view.backgroundColor = .systemGroupedBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 180
        tableView.register(FeedCell.self, forCellReuseIdentifier: "CollectionCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableHeaderView = makeHeader()
        loadRemoteItems()
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadRemoteItems() {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else { return }
        RemoteLibraryRepository.shared.fetchSavedItems { [weak self] result in
            guard let self = self else { return }
            if case let .success(items) = result, !items.isEmpty {
                self.items = items
                self.tableView.reloadData()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView,
              header.frame.width != tableView.bounds.width,
              tableView.bounds.width > 0 else { return }
        header.frame.size.width = tableView.bounds.width
        tableView.tableHeaderView = header
    }

    private func makeHeader() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 76))
        let title = UILabel()
        title.text = "稍后阅读"
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let detail = UILabel()
        detail.text = "离线演示收藏 · 3 条内容"
        detail.textColor = AppTheme.secondaryText
        detail.font = .systemFont(ofSize: 13)
        let stack = UIStackView(arrangedSubviews: [title, detail])
        stack.axis = .vertical
        stack.spacing = 4
        header.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 16)
        ])
        return header
    }
}

extension CollectionsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CollectionCell", for: indexPath) as! FeedCell
        cell.configure(with: items[indexPath.row])
        return cell
    }
}

extension CollectionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(DetailViewController(item: items[indexPath.row]), animated: true)
    }
}
