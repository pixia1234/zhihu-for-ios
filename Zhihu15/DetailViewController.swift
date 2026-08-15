import UIKit

final class DetailViewController: UIViewController {
    private let item: FeedItem
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let actionBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let actionsStack = UIStackView()
    private let titleLabel = UILabel()
    private let richContentView = RichContentView()
    private let primaryActionButton = UIButton(type: .system)
    private let managesNavigationBar: Bool
    private var collectionActionButton: UIButton?
    private var actionBarBottomConstraint: NSLayoutConstraint?
    private var actionBarHeightConstraint: NSLayoutConstraint?
    private var canonicalURL: URL?
    private var displayedUpvotes: Int
    private var hasVoted = false
    private var displayedFavoriteCount: Int
    private var hasLoadedFavoriteCount = false
    private var isFavorited = false
    private var isVoting = false
    private var isLoadingCollectionState = false
    private var didHideTabBar = false

    init(item: FeedItem, managesNavigationBar: Bool = false) {
        self.item = item
        self.managesNavigationBar = managesNavigationBar
        self.displayedUpvotes = item.upvotes
        self.hasVoted = item.isVoted
        self.displayedFavoriteCount = item.favoriteCount
        self.hasLoadedFavoriteCount = item.favoriteCount > 0
        self.isFavorited = item.isFavorited
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.kind.rawValue
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground
        if !managesNavigationBar {
            navigationItem.rightBarButtonItems = makeNavigationBarItems()
        }
        setupActionBar()
        setupScrollView()
        buildContent()
        loadRemoteContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        BrowsingHistoryStore.shared.record(item)
        HandoffCoordinator.shared.start(item: item)
        loadCollectionState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // A detail controller hosted by SwiftUI's TabView can retain the
        // TabView height in its safeAreaInsets after the tab bar is hidden.
        // Use the window's physical safe area (home indicator only) instead
        // of the inherited child safe area, so the action bar moves down with
        // the hidden tab bar on iPhone and iPad.
        let bottomInset = max(0, view.window?.safeAreaInsets.bottom ?? 0)
        let constant = -bottomInset
        if actionBarBottomConstraint?.constant != constant {
            actionBarBottomConstraint?.constant = constant
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // SwiftUI can reuse a navigation item when this controller is hosted
        // by NavigationLink. Do not allow an old author ID/headline prompt to
        // make the answer navigation bar taller.
        navigationItem.prompt = nil
        navigationItem.largeTitleDisplayMode = .never
        if let tabBar = tabBarController?.tabBar {
            tabBar.isHidden = true
            didHideTabBar = true
        }
        AppTheme.setTabBarHidden(true)
        view.setNeedsLayout()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard didHideTabBar else { return }
        let remainsInNavigationStack = navigationController?.viewControllers.contains { $0 === self } == true
        if isMovingFromParent || navigationController?.isBeingDismissed == true || !remainsInNavigationStack {
            tabBarController?.tabBar.isHidden = false
            AppTheme.setTabBarHidden(false)
            didHideTabBar = false
        }
    }

    deinit {
        HandoffCoordinator.shared.stop()
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // This controller is used both as a normal UIKit push and as a
        // UIViewControllerRepresentable inside SwiftUI NavigationLink. In
        // the latter case UIKit's automatic scroll inset is applied on top
        // of SwiftUI's safe area, producing the large blank band below the
        // navigation bar. Manage the safe area explicitly instead.
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionBar.topAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 22, left: 20, bottom: 32, right: 20)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func makeNavigationBarItems() -> [UIBarButtonItem] {
        var actions: [UIBarButtonItem] = []
        if item.kind == .video {
            let play = UIBarButtonItem(image: UIImage(systemName: "play.circle"), style: .plain, target: self, action: #selector(openVideo))
            play.accessibilityLabel = "播放"
            actions.insert(play, at: 0)
        }
        let browser = UIBarButtonItem(image: UIImage(systemName: "safari"), style: .plain, target: self, action: #selector(openCanonicalURL))
        browser.accessibilityLabel = "在知乎打开"
        actions.append(browser)
        return actions
    }

    func openCanonicalURLFromNavigationHost() {
        openCanonicalURL()
    }

    func openVideoFromNavigationHost() {
        openVideo()
    }

    private func setupActionBar() {
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionBar.clipsToBounds = true
        view.addSubview(actionBar)
        actionBarBottomConstraint = actionBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        actionBarHeightConstraint = actionBar.heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([
            actionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionBarBottomConstraint!,
            actionBarHeightConstraint!
        ])

        actionsStack.axis = .horizontal
        actionsStack.spacing = 10
        actionsStack.distribution = .fillEqually
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionBar.contentView.addSubview(actionsStack)
        NSLayoutConstraint.activate([
            actionsStack.leadingAnchor.constraint(equalTo: actionBar.contentView.leadingAnchor, constant: 16),
            actionsStack.trailingAnchor.constraint(equalTo: actionBar.contentView.trailingAnchor, constant: -16),
            actionsStack.topAnchor.constraint(equalTo: actionBar.contentView.topAnchor, constant: 6),
            actionsStack.bottomAnchor.constraint(equalTo: actionBar.contentView.bottomAnchor, constant: -6)
        ])

        updatePrimaryActionTitle()
        primaryActionButton.setImage(UIImage(systemName: item.kind == .question ? "person.badge.plus" : (hasVoted ? "arrow.up.circle.fill" : "arrow.up")), for: .normal)
        primaryActionButton.tintColor = AppTheme.zhihuBlue
        primaryActionButton.setTitleColor(AppTheme.zhihuBlue, for: .normal)
        primaryActionButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        primaryActionButton.backgroundColor = AppTheme.zhihuBlue.withAlphaComponent(0.08)
        primaryActionButton.layer.cornerRadius = 9
        primaryActionButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 4, bottom: 7, right: 4)
        primaryActionButton.addTarget(self, action: #selector(primaryAction), for: .touchUpInside)
        actionsStack.addArrangedSubview(primaryActionButton)
        let commentsButton = actionButton(title: "\(max(0, item.comments))", image: "bubble.left")
        commentsButton.accessibilityLabel = "评论，\(max(0, item.comments))"
        commentsButton.addTarget(self, action: #selector(openComments), for: .touchUpInside)
        actionsStack.addArrangedSubview(commentsButton)
        let collectionButton = actionButton(title: "", image: "bookmark")
        let loggedIn = ZhihuAccountStore.shared.load()?.isLoggedIn == true
        let initialFavoriteTitle: String
        if hasLoadedFavoriteCount || !loggedIn {
            initialFavoriteTitle = "\(max(0, displayedFavoriteCount))"
        } else {
            initialFavoriteTitle = "…"
        }
        collectionButton.setTitle(initialFavoriteTitle, for: .normal)
        collectionButton.setImage(UIImage(systemName: isFavorited ? "bookmark.fill" : "bookmark"), for: .normal)
        collectionButton.accessibilityLabel = loggedIn ? "收藏夹数量加载中" : "收藏，未登录"
        collectionButton.addTarget(self, action: #selector(openCollectionPicker), for: .touchUpInside)
        collectionActionButton = collectionButton
        actionsStack.addArrangedSubview(collectionButton)
    }

    private func buildContent() {
        let authorRow = UIStackView()
        authorRow.axis = .horizontal
        authorRow.alignment = .center
        authorRow.spacing = 10
        let avatar = AvatarView()
        avatar.configure(name: item.author, color: item.avatarColor)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 42),
            avatar.heightAnchor.constraint(equalToConstant: 42)
        ])
        if let url = item.avatarURL {
            ImagePipeline.shared.image(for: url) { [weak avatar] image in
                avatar?.setImage(image)
            }
        }
        authorRow.addArrangedSubview(avatar)
        let authorInfo = UIStackView()
        authorInfo.axis = .vertical
        authorInfo.spacing = 3
        let author = UILabel()
        author.text = item.author
        author.font = .systemFont(ofSize: 16, weight: .semibold)
        let role = UILabel()
        role.text = item.authorRole
        role.textColor = AppTheme.secondaryText
        role.font = .systemFont(ofSize: 13)
        authorInfo.addArrangedSubview(author)
        authorInfo.addArrangedSubview(role)
        authorRow.addArrangedSubview(authorInfo)
        authorRow.addArrangedSubview(UIView())
        contentStack.addArrangedSubview(authorRow)

        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 25, weight: .bold)
        titleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(titleLabel)

        contentStack.addArrangedSubview(makeDivider())

        if let thumbnailURL = item.thumbnailURL {
            let imagePlaceholder = UIView()
            imagePlaceholder.backgroundColor = item.imageColor
            imagePlaceholder.layer.cornerRadius = 12
            imagePlaceholder.heightAnchor.constraint(equalToConstant: 190).isActive = true
            let imageIcon = UIImageView(image: UIImage(systemName: item.kind == .video ? "play.circle.fill" : "photo.on.rectangle.angled"))
            imageIcon.tintColor = AppTheme.zhihuBlue.withAlphaComponent(0.75)
            imageIcon.translatesAutoresizingMaskIntoConstraints = false
            imagePlaceholder.addSubview(imageIcon)
            NSLayoutConstraint.activate([
                imageIcon.centerXAnchor.constraint(equalTo: imagePlaceholder.centerXAnchor),
                imageIcon.centerYAnchor.constraint(equalTo: imagePlaceholder.centerYAnchor),
                imageIcon.widthAnchor.constraint(equalToConstant: 44),
                imageIcon.heightAnchor.constraint(equalToConstant: 44)
            ])
            let preview = UIImageView()
            preview.contentMode = .scaleAspectFill
            preview.clipsToBounds = true
            preview.layer.cornerRadius = 12
            preview.translatesAutoresizingMaskIntoConstraints = false
            imagePlaceholder.insertSubview(preview, at: 0)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: imagePlaceholder.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: imagePlaceholder.trailingAnchor),
                preview.topAnchor.constraint(equalTo: imagePlaceholder.topAnchor),
                preview.bottomAnchor.constraint(equalTo: imagePlaceholder.bottomAnchor)
            ])
            ImagePipeline.shared.image(for: thumbnailURL) { image in
                preview.image = image
                imageIcon.isHidden = image != nil
            }
            contentStack.addArrangedSubview(imagePlaceholder)
        }

        richContentView.onOpenURL = { [weak self] url in self?.openContentURL(url) }
        richContentView.load(markup: item.excerpt)
        contentStack.addArrangedSubview(richContentView)

        contentStack.addArrangedSubview(makeDivider())

        if item.kind == .question {
            let answersButton = UIButton(type: .system)
            answersButton.setTitle("查看全部回答", for: .normal)
            answersButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
            answersButton.semanticContentAttribute = .forceRightToLeft
            answersButton.contentHorizontalAlignment = .left
            answersButton.tintColor = AppTheme.zhihuBlue
            answersButton.setTitleColor(AppTheme.zhihuBlue, for: .normal)
            answersButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            answersButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
            answersButton.addTarget(self, action: #selector(openAnswers), for: .touchUpInside)
            contentStack.addArrangedSubview(answersButton)
        }

        if item.kind == .answer, questionItemForAnswer() != nil {
            let nextAnswerButton = UIButton(type: .system)
            nextAnswerButton.setTitle("继续查看下一个回答", for: .normal)
            nextAnswerButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
            nextAnswerButton.semanticContentAttribute = .forceRightToLeft
            nextAnswerButton.contentHorizontalAlignment = .left
            nextAnswerButton.tintColor = AppTheme.zhihuBlue
            nextAnswerButton.setTitleColor(AppTheme.zhihuBlue, for: .normal)
            nextAnswerButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            nextAnswerButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
            nextAnswerButton.addTarget(self, action: #selector(openRelatedAnswers), for: .touchUpInside)
            contentStack.addArrangedSubview(nextAnswerButton)
        }
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = AppTheme.border
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func questionItemForAnswer() -> FeedItem? {
        guard item.kind == .answer, let questionID = item.questionID, questionID > 0 else { return nil }
        return FeedItem(
            id: Int(questionID),
            kind: .question,
            author: "知乎问题",
            authorRole: "",
            avatarColor: AppTheme.zhihuBlue,
            title: item.title,
            excerpt: "",
            topic: item.topic,
            upvotes: 0,
            comments: 0,
            hasImage: false,
            imageColor: AppTheme.zhihuBlue.withAlphaComponent(0.08),
            contentID: questionID
        )
    }

    private func loadRemoteContent() {
        guard item.contentID != nil else { return }
        RemoteContentRepository.shared.fetch(item: item) { [weak self] result in
            guard let self = self else { return }
            if case let .success(content) = result {
                self.titleLabel.text = content.title
                if let upvoteCount = content.upvoteCount { self.displayedUpvotes = upvoteCount }
                if let isVoted = content.isVoted { self.hasVoted = isVoted }
                if let favoriteCount = content.favoriteCount {
                    self.displayedFavoriteCount = max(0, favoriteCount)
                    self.hasLoadedFavoriteCount = true
                }
                if let isFavorited = content.isFavorited { self.isFavorited = isFavorited }
                self.updatePrimaryActionTitle()
                self.updateFavoriteButton()
                self.richContentView.load(markup: content.bodyHTML.isEmpty ? content.body : content.bodyHTML)
                if let url = content.canonicalURL {
                    self.navigationItem.rightBarButtonItems?.last?.accessibilityLabel = "在知乎打开"
                    self.canonicalURL = url
                }
            } else {
                self.richContentView.load(markup: self.item.excerpt + "\n\n暂时无法读取网络正文，请稍后重试。")
            }
        }
    }

    @objc private func openComments() {
        push(CommentsViewController(item: item))
    }

    @objc private func openAnswers() {
        guard item.kind == .question else { return }
        let questionID = item.contentID ?? item.questionID ?? 0
        guard questionID > 0 else {
            showActionResult(.failure(ZhihuSessionError.malformedPayload), success: "")
            return
        }
        push(QuestionAnswersViewController(question: item))
    }

    @objc private func openRelatedAnswers() {
        guard let question = questionItemForAnswer() else { return }
        push(QuestionAnswersViewController(question: question, excludingAnswerID: item.contentID))
    }

    @objc private func openVideo() {
        push(VideoPlaybackViewController(item: item))
    }

    @objc private func openCanonicalURL() {
        guard let url = canonicalURL ?? RemoteContentRepository.canonicalURLForDisplay(item) else { return }
        openContentURL(url)
    }

    private func openContentURL(_ url: URL) {
        guard url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" else { return }
        if url.host?.lowercased().hasSuffix("zhihu.com") == true {
            push(WebContentViewController(url: url, title: "知乎内容"))
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func push(_ controller: UIViewController) {
        controller.hidesBottomBarWhenPushed = true
        if let navigationController {
            navigationController.pushViewController(controller, animated: true)
        } else {
            present(UINavigationController(rootViewController: controller), animated: true)
        }
    }

    @objc private func primaryAction() {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
            let login = UINavigationController(rootViewController: LoginViewController())
            present(login, animated: true)
            return
        }
        if item.kind == .question {
            let questionID = item.contentID ?? item.questionID ?? 0
            guard questionID > 0 else {
                showActionResult(.failure(ZhihuSessionError.malformedPayload), success: "")
                return
            }
            ZhihuActionRepository.shared.follow(questionID: questionID, following: true) { [weak self] result in
                self?.showActionResult(result, success: "已关注这个问题")
            }
        } else if let contentID = item.contentID, contentID > 0 {
            guard !isVoting else { return }
            let requestedVote = !hasVoted
            isVoting = true
            primaryActionButton.isEnabled = false
            ZhihuActionRepository.shared.vote(contentID: contentID, kind: item.kind, up: requestedVote) { [weak self] result in
                guard let self = self else { return }
                self.isVoting = false
                if case let .success(mutation) = result {
                    if let serverCount = mutation.upvoteCount {
                        self.displayedUpvotes = max(0, serverCount)
                    } else if self.hasVoted != mutation.isVoted {
                        self.displayedUpvotes = max(0, self.displayedUpvotes + (mutation.isVoted ? 1 : -1))
                    }
                    self.hasVoted = mutation.isVoted
                    self.updatePrimaryActionTitle()
                }
                self.primaryActionButton.isEnabled = true
                self.showActionResult(result.map { _ in () }, success: requestedVote ? "已赞同" : "已取消赞同")
            }
        } else {
            showActionResult(.failure(ZhihuSessionError.malformedPayload), success: "")
        }
    }

    private func updatePrimaryActionTitle() {
        guard item.kind != .question else {
            primaryActionButton.setTitle(nil, for: .normal)
            primaryActionButton.accessibilityLabel = "关注问题"
            return
        }
        primaryActionButton.setTitle("\(max(0, displayedUpvotes))", for: .normal)
        primaryActionButton.setImage(UIImage(systemName: hasVoted ? "arrow.up.circle.fill" : "arrow.up"), for: .normal)
        primaryActionButton.accessibilityLabel = hasVoted ? "取消赞同，\(max(0, displayedUpvotes))" : "赞同，\(max(0, displayedUpvotes))"
    }

    @objc private func openCollectionPicker() {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
            present(UINavigationController(rootViewController: LoginViewController()), animated: true)
            return
        }
        ZhihuActionRepository.shared.fetchCollections(for: item) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .failure(error): self.showActionResult(.failure(error), success: "")
            case let .success(options):
                guard !options.isEmpty else {
                    self.showActionResult(.failure(ZhihuSessionError.malformedPayload), success: "")
                    return
                }
                let selectedCount = options.filter(\.isSelected).count
                self.updateCollectionButton(selectedCount: selectedCount)
                let alert = UIAlertController(title: "收藏到", message: nil, preferredStyle: .actionSheet)
                for option in options {
                    let title = option.isSelected ? "✓ \(option.title)（移除）" : option.title
                    alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                        guard let self = self else { return }
                        ZhihuActionRepository.shared.setCollection(!option.isSelected, collectionID: option.id, for: self.item) { [weak self] result in
                            guard let self = self else { return }
                            if case .success = result {
                                let count = max(0, selectedCount + (option.isSelected ? -1 : 1))
                                if self.hasLoadedFavoriteCount {
                                    self.displayedFavoriteCount = max(0, self.displayedFavoriteCount + (option.isSelected ? -1 : 1))
                                }
                                self.updateCollectionButton(selectedCount: count)
                            }
                            self.showActionResult(result, success: option.isSelected ? "已从收藏夹移除" : "已加入收藏夹")
                        }
                    })
                }
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                if let popover = alert.popoverPresentationController {
                    popover.sourceView = self.view
                    popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                }
                self.present(alert, animated: true)
            }
        }
    }

    private func loadCollectionState() {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true,
              item.contentID != nil,
              !isLoadingCollectionState else { return }
        isLoadingCollectionState = true
        ZhihuActionRepository.shared.fetchCollections(for: item) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingCollectionState = false
            guard case let .success(options) = result else { return }
            self.updateCollectionButton(selectedCount: options.filter(\.isSelected).count)
        }
    }

    private func updateCollectionButton(selectedCount: Int) {
        isFavorited = selectedCount > 0
        // If the content endpoint has not returned favlists_count yet, the
        // selected-folder count is the best accurate fallback for this user.
        if !hasLoadedFavoriteCount {
            displayedFavoriteCount = max(0, selectedCount)
            hasLoadedFavoriteCount = true
        }
        updateFavoriteButton()
    }

    private func updateFavoriteButton() {
        let count = max(0, displayedFavoriteCount)
        collectionActionButton?.setTitle("\(count)", for: .normal)
        collectionActionButton?.setImage(UIImage(systemName: isFavorited ? "bookmark.fill" : "bookmark"), for: .normal)
        collectionActionButton?.accessibilityLabel = "收藏，\(count)"
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

    private func actionButton(title: String, image: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = AppTheme.zhihuBlue
        button.setTitleColor(AppTheme.zhihuBlue, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = AppTheme.zhihuBlue.withAlphaComponent(0.08)
        button.layer.cornerRadius = 9
        button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 4, bottom: 7, right: 4)
        return button
    }
}
