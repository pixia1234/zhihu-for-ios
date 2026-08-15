import UIKit

final class HomeViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let channelControl = UISegmentedControl(items: ["推荐", "关注", "热榜", "日报"])
    private let headerSubtitle = UILabel()
    private let refreshControl = UIRefreshControl()
    private var items = SampleData.recommendations
    private var locallyVotedItemIDs = Set<Int>()
    private var nextPageURL: URL?
    private var isLoadingMore = false
    private var autoRefreshTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "首页"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), style: .plain, target: self, action: #selector(openCreation)),
            UIBarButtonItem(image: UIImage(systemName: "bell"), style: .plain, target: self, action: #selector(openNotifications))
        ]
        setupTableView()
        setupHeader()
        loadRemote(channel: .recommendation)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadRemote(channel: HomeChannel(rawValue: self.channelControl.selectedSegmentIndex) ?? .recommendation)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    deinit { autoRefreshTimer?.invalidate() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView,
              header.frame.width != tableView.bounds.width,
              tableView.bounds.width > 0 else { return }
        header.frame.size.width = tableView.bounds.width
        tableView.tableHeaderView = header
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 190
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        tableView.delaysContentTouches = false
        tableView.register(FeedCell.self, forCellReuseIdentifier: "FeedCell")
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

    private func setupHeader() {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 104))
        header.backgroundColor = .systemGroupedBackground

        let searchButton = UIButton(type: .system)
        searchButton.backgroundColor = .secondarySystemGroupedBackground
        searchButton.layer.cornerRadius = 10
        searchButton.contentHorizontalAlignment = .left
        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchButton.setTitle("  搜索你感兴趣的内容", for: .normal)
        searchButton.setTitleColor(AppTheme.secondaryText, for: .normal)
        searchButton.tintColor = AppTheme.secondaryText
        searchButton.titleLabel?.font = .systemFont(ofSize: 15)
        searchButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 13, bottom: 0, right: 13)
        searchButton.addTarget(self, action: #selector(openSearch), for: .touchUpInside)
        header.addSubview(searchButton)

        channelControl.selectedSegmentIndex = 0
        channelControl.selectedSegmentTintColor = AppTheme.zhihuBlue
        channelControl.setTitleTextAttributes([.foregroundColor: AppTheme.secondaryText, .font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .normal)
        channelControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
        channelControl.addTarget(self, action: #selector(channelChanged), for: .valueChanged)
        header.addSubview(channelControl)

        headerSubtitle.text = "为你推荐 · 内容每次打开都会重新整理"
        headerSubtitle.textColor = AppTheme.secondaryText
        headerSubtitle.font = .systemFont(ofSize: 12)
        header.addSubview(headerSubtitle)

        searchButton.translatesAutoresizingMaskIntoConstraints = false
        channelControl.translatesAutoresizingMaskIntoConstraints = false
        headerSubtitle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            searchButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            searchButton.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            searchButton.heightAnchor.constraint(equalToConstant: 42),
            channelControl.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            channelControl.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            channelControl.topAnchor.constraint(equalTo: searchButton.bottomAnchor, constant: 12),
            channelControl.heightAnchor.constraint(equalToConstant: 32),
            headerSubtitle.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            headerSubtitle.topAnchor.constraint(equalTo: channelControl.bottomAnchor, constant: 8)
        ])
        header.frame.size.height = 142
        tableView.tableHeaderView = header
    }

    @objc private func channelChanged() {
        items = SampleData.feedItems(for: channelControl.selectedSegmentIndex)
        nextPageURL = nil
        headerSubtitle.text = channelControl.selectedSegmentIndex == 2 ? "热榜 · 实时更新的热门讨论" : "为你推荐 · 内容每次打开都会重新整理"
        tableView.reloadData()
        tableView.setContentOffset(.zero, animated: false)
        loadRemote(channel: HomeChannel(rawValue: channelControl.selectedSegmentIndex) ?? .recommendation)
    }

    @objc private func refresh() {
        loadRemote(channel: HomeChannel(rawValue: channelControl.selectedSegmentIndex) ?? .recommendation, endRefreshing: true)
    }

    private func loadRemote(channel: HomeChannel, endRefreshing: Bool = false) {
        nextPageURL = nil
        RemoteFeedRepository.shared.fetchPage(channel: channel) { [weak self] result in
            guard let self = self else { return }
            if endRefreshing { self.refreshControl.endRefreshing() }
            guard self.channelControl.selectedSegmentIndex == channel.rawValue else { return }
            if case let .success(page) = result, !page.items.isEmpty {
                self.items = page.items
                self.nextPageURL = page.nextURL
                self.headerSubtitle.text = channel == .hot ? "热榜 · 实时更新的热门讨论" : "知乎实时内容 · 已启用本地图片缓存"
                self.tableView.reloadData()
            }
        }
    }

    private func loadMore() {
        guard !isLoadingMore,
              let nextPageURL,
              let channel = HomeChannel(rawValue: channelControl.selectedSegmentIndex) else { return }
        isLoadingMore = true
        RemoteFeedRepository.shared.fetchPage(channel: channel, nextURL: nextPageURL) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingMore = false
            guard case let .success(page) = result else { return }
            let existingIDs = Set(self.items.map(\.id))
            self.items.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            self.nextPageURL = page.nextURL
            self.tableView.reloadData()
        }
    }

    @objc private func openSearch() {
        navigationController?.pushViewController(SearchViewController(), animated: true)
    }

    @objc private func openNotifications() {
        navigationController?.pushViewController(MessagesViewController(), animated: true)
    }

    @objc private func openCreation() {
        let alert = UIAlertController(title: "开始创作", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "发想法", style: .default) { [weak self] _ in
            let controller = UINavigationController(rootViewController: RichTextEditorViewController(mode: .pin))
            self?.present(controller, animated: true)
        })
        alert.addAction(UIAlertAction(title: "写回答", style: .default) { [weak self] _ in
            self?.askForQuestion()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(alert, animated: true)
    }

    private func askForQuestion() {
        let alert = UIAlertController(title: "写回答", message: "请输入知乎问题 ID", preferredStyle: .alert)
        alert.addTextField { field in field.keyboardType = .numberPad; field.placeholder = "例如 123456789" }
        alert.addTextField { field in field.placeholder = "问题标题（可选）" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "继续", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let idText = alert?.textFields?.first?.text, let id = Int64(idText) else { return }
            let title = alert?.textFields?.dropFirst().first?.text ?? "知乎问题"
            let controller = UINavigationController(rootViewController: RichTextEditorViewController(mode: .answer(questionID: id, questionTitle: title.isEmpty ? "知乎问题" : title)))
            self.present(controller, animated: true)
        })
        present(alert, animated: true)
    }

    private func showDetail(for item: FeedItem) {
        if item.kind == .video {
            navigationController?.pushViewController(VideoPlaybackViewController(item: item), animated: true)
        } else {
            navigationController?.pushViewController(DetailViewController(item: item), animated: true)
        }
    }

    private func handle(_ action: FeedCell.Action, item: FeedItem) {
        switch action {
        case .upvote:
            guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
                present(UINavigationController(rootViewController: LoginViewController()), animated: true)
                return
            }
            if item.kind == .question, let questionID = item.contentID ?? item.questionID, questionID > 0 {
                ZhihuActionRepository.shared.follow(questionID: questionID, following: true) { [weak self] result in
                    self?.showActionResult(result, success: "已关注这个问题")
                }
            } else if item.kind == .answer, let answerID = item.contentID, answerID > 0 {
                ZhihuActionRepository.shared.vote(answerID: answerID, up: true) { [weak self] result in
                    guard let self = self else { return }
                    if case .success = result {
                        self.markLocallyVoted(item)
                    }
                    self.showActionResult(result, success: "已赞同")
                }
            } else {
                showActionResult(.failure(ZhihuSessionError.malformedPayload), success: "")
            }
        case .comment:
            showDetail(for: item)
        case .share:
            let share = UIActivityViewController(activityItems: [item.title], applicationActivities: nil)
            if let popover = share.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
            present(share, animated: true)
        }
    }

    private func markLocallyVoted(_ item: FeedItem) {
        guard !locallyVotedItemIDs.contains(item.id),
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        locallyVotedItemIDs.insert(item.id)
        items[index].upvotes += 1
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
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
}

extension HomeViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FeedCell", for: indexPath) as! FeedCell
        let item = items[indexPath.row]
        cell.configure(with: item)
        cell.onAction = { [weak self] action in self?.handle(action, item: item) }
        return cell
    }
}

extension HomeViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= items.count - 3 { loadMore() }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        showDetail(for: items[indexPath.row])
    }
}
