import UIKit

final class QuestionAnswersViewController: UIViewController {
    private let question: FeedItem
    private let excludingAnswerID: Int64?
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private var answers: [FeedItem] = []
    private var nextPageURL: URL?
    private var isLoading = false
    private var isLoadingMore = false

    init(question: FeedItem, excludingAnswerID: Int64? = nil) {
        self.question = question
        self.excludingAnswerID = excludingAnswerID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "全部回答"
        view.backgroundColor = .systemGroupedBackground
        setupTableView()
        loadAnswers(refreshing: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The detail page owns the native bottom toolbar. The answers list
        // must take it out of the navigation layout while it is visible, so
        // the toolbar can animate back with the detail page on pop.
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            navigationController?.setToolbarHidden(false, animated: animated)
        }
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 190
        tableView.register(FeedCell.self, forCellReuseIdentifier: "QuestionAnswerCell")
        tableView.dataSource = self
        tableView.delegate = self
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func refresh() {
        loadAnswers(refreshing: true)
    }

    private func loadAnswers(refreshing: Bool) {
        guard !isLoading, !isLoadingMore else {
            if refreshing { refreshControl.endRefreshing() }
            return
        }
        isLoading = true
        QuestionAnswersRepository.shared.fetch(question: question) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            if refreshing { self.refreshControl.endRefreshing() }
            switch result {
            case let .success(page):
                self.answers = page.items.filter { $0.contentID != self.excludingAnswerID }
                self.nextPageURL = page.nextURL
                self.tableView.reloadData()
                if self.answers.isEmpty, self.nextPageURL != nil {
                    self.loadMore()
                }
            case let .failure(error):
                self.showError(error)
            }
        }
    }

    private func loadMore() {
        guard !isLoading, !isLoadingMore, let nextPageURL else { return }
        isLoadingMore = true
        QuestionAnswersRepository.shared.fetch(question: question, nextURL: nextPageURL) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingMore = false
            guard case let .success(page) = result else { return }
            let existingIDs = Set(self.answers.map(\.id))
            self.answers.append(contentsOf: page.items.filter { $0.contentID != self.excludingAnswerID && !existingIDs.contains($0.id) })
            self.nextPageURL = page.nextURL
            self.tableView.reloadData()
        }
    }

    private func open(_ item: FeedItem) {
        navigationController?.pushViewController(makeSwiftUIDetailViewController(item: item), animated: true)
    }

    private func handle(_ action: FeedCell.Action, item: FeedItem) {
        switch action {
        case .upvote:
            guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
                present(UINavigationController(rootViewController: LoginViewController()), animated: true)
                return
            }
            guard let contentID = item.contentID, contentID > 0 else {
                showActionResult(.failure(ZhihuSessionError.malformedPayload), success: "")
                return
            }
            let requestedVote = !item.isVoted
            ZhihuActionRepository.shared.vote(contentID: contentID, kind: item.kind, up: requestedVote) { [weak self] result in
                guard let self = self else { return }
                if case let .success(mutation) = result,
                   let index = self.answers.firstIndex(where: { $0.id == item.id }) {
                    self.answers[index].isVoted = mutation.isVoted
                    if let serverCount = mutation.upvoteCount {
                        self.answers[index].upvotes = max(0, serverCount)
                    } else {
                        self.answers[index].upvotes = max(0, self.answers[index].upvotes + (mutation.isVoted ? 1 : -1))
                    }
                    self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
                }
                self.showActionResult(result.map { _ in () }, success: requestedVote ? "已赞同" : "已取消赞同")
            }
        case .comment:
            navigationController?.pushViewController(CommentsViewController(item: item), animated: true)
        case .share:
            let share = UIActivityViewController(activityItems: [item.title], applicationActivities: nil)
            if let popover = share.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
            present(share, animated: true)
        }
    }

    private func showActionResult(_ result: Result<Void, Error>, success: String) {
        let message: String
        switch result {
        case .success: message = success
        case let .failure(error): message = error.localizedDescription
        }
        let alert = UIAlertController(title: "知乎", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        present(alert, animated: true)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "回答加载失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in self?.loadAnswers(refreshing: false) })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
}

extension QuestionAnswersViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { answers.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "QuestionAnswerCell", for: indexPath) as! FeedCell
        let item = answers[indexPath.row]
        cell.configure(with: item)
        cell.onAction = { [weak self] action in self?.handle(action, item: item) }
        return cell
    }
}

extension QuestionAnswersViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= answers.count - 3 { loadMore() }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard answers.indices.contains(indexPath.row) else { return }
        open(answers[indexPath.row])
    }
}
