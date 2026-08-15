import UIKit

final class SearchViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private var results: [FeedItem] = []
    private var lastQuery = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "搜索"
        view.backgroundColor = .systemGroupedBackground
        if navigationController?.presentingViewController != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeSearch)
            )
        }
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索问题、话题或用户"
        searchController.searchBar.searchTextField.backgroundColor = .secondarySystemGroupedBackground
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 170
        tableView.register(FeedCell.self, forCellReuseIdentifier: "SearchFeedCell")
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateEmptyState()
    }

    @objc private func closeSearch() {
        dismiss(animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if navigationController?.viewControllers.last === self {
            searchController.searchBar.becomeFirstResponder()
        }
    }

    private func updateEmptyState() {
        guard results.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        let empty = UIView()
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = AppTheme.zhihuBlue
        icon.contentMode = .scaleAspectFit
        let label = UILabel()
        label.text = "输入关键词，开始探索知乎"
        label.textColor = AppTheme.secondaryText
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        empty.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 32), icon.heightAnchor.constraint(equalToConstant: 32),
            stack.centerXAnchor.constraint(equalTo: empty.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: empty.centerYAnchor)
        ])
        tableView.backgroundView = empty
    }
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if query.isEmpty {
            results = []
        } else {
            results = SampleData.allFeedItems.filter { item in
                item.title.localizedCaseInsensitiveContains(query) || item.excerpt.localizedCaseInsensitiveContains(query) || item.topic.localizedCaseInsensitiveContains(query)
            }
            lastQuery = query
            RemoteFeedRepository.shared.search(query: query) { [weak self] result in
                guard let self = self, self.lastQuery == query else { return }
                if case let .success(remoteResults) = result, !remoteResults.isEmpty {
                    self.results = remoteResults
                    self.tableView.reloadData()
                    self.updateEmptyState()
                }
            }
        }
        tableView.reloadData()
        updateEmptyState()
    }
}

extension SearchViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchFeedCell", for: indexPath) as! FeedCell
        cell.configure(with: results[indexPath.row])
        cell.onAction = { [weak self] action in
            guard action == .comment, let self = self else { return }
            guard indexPath.row < self.results.count else { return }
            self.navigationController?.pushViewController(DetailViewController(item: self.results[indexPath.row]), animated: true)
        }
        return cell
    }
}

extension SearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(DetailViewController(item: results[indexPath.row]), animated: true)
    }
}
