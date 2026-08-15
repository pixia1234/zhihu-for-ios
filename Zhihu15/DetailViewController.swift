import UIKit

final class DetailViewController: UIViewController {
    private let item: FeedItem
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let primaryActionButton = UIButton(type: .system)

    init(item: FeedItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.kind.rawValue
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "评论", style: .plain, target: self, action: #selector(openComments))
        if item.kind == .video {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: "播放", style: .plain, target: self, action: #selector(openVideo)),
                UIBarButtonItem(title: "评论", style: .plain, target: self, action: #selector(openComments))
            ]
        }
        setupScrollView()
        buildContent()
        loadRemoteContent()
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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

        let topic = PillLabel(text: item.topic)
        contentStack.addArrangedSubview(topic)

        if item.hasImage {
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
            contentStack.addArrangedSubview(imagePlaceholder)
        }

        bodyLabel.text = item.excerpt + "\n\n正在读取完整内容…"
        bodyLabel.font = .systemFont(ofSize: 18)
        bodyLabel.textColor = AppTheme.text
        bodyLabel.numberOfLines = 0
        bodyLabel.setContentHuggingPriority(.required, for: .vertical)
        contentStack.addArrangedSubview(bodyLabel)

        let divider = UIView()
        divider.backgroundColor = AppTheme.border
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        contentStack.addArrangedSubview(divider)

        let actions = UIStackView()
        actions.axis = .horizontal
        actions.spacing = 10
        actions.distribution = .fillEqually
        primaryActionButton.setTitle(item.kind == .question ? "关注问题" : "\(item.upvotes > 0 ? item.upvotes : 0) 赞同", for: .normal)
        primaryActionButton.setImage(UIImage(systemName: item.kind == .question ? "person.badge.plus" : "arrow.up"), for: .normal)
        primaryActionButton.tintColor = AppTheme.zhihuBlue
        primaryActionButton.setTitleColor(AppTheme.zhihuBlue, for: .normal)
        primaryActionButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        primaryActionButton.backgroundColor = AppTheme.zhihuBlue.withAlphaComponent(0.08)
        primaryActionButton.layer.cornerRadius = 9
        primaryActionButton.contentEdgeInsets = UIEdgeInsets(top: 11, left: 4, bottom: 11, right: 4)
        primaryActionButton.addTarget(self, action: #selector(primaryAction), for: .touchUpInside)
        actions.addArrangedSubview(primaryActionButton)
        actions.addArrangedSubview(actionButton(title: "\(item.comments > 0 ? item.comments : 0) 评论", image: "bubble.left"))
        actions.addArrangedSubview(actionButton(title: "收藏", image: "bookmark"))
        contentStack.addArrangedSubview(actions)

        let relatedTitle = UILabel()
        relatedTitle.text = "相关内容"
        relatedTitle.font = .systemFont(ofSize: 19, weight: .semibold)
        contentStack.addArrangedSubview(relatedTitle)

        let related = UILabel()
        related.text = "继续阅读与“\(item.topic)”相关的优质回答，发现更多不同角度的思考。"
        related.textColor = AppTheme.secondaryText
        related.font = .systemFont(ofSize: 16)
        related.numberOfLines = 0
        contentStack.addArrangedSubview(related)
    }

    private func loadRemoteContent() {
        guard item.contentID != nil else { return }
        RemoteContentRepository.shared.fetch(item: item) { [weak self] result in
            guard let self = self else { return }
            if case let .success(content) = result {
                self.titleLabel.text = content.title
                let authorText = [content.author, content.authorHeadline].compactMap { $0 }.joined(separator: " · ")
                self.bodyLabel.text = content.body.isEmpty ? self.item.excerpt : content.body
                self.navigationItem.prompt = authorText.isEmpty ? nil : authorText
            } else {
                self.bodyLabel.text = self.item.excerpt + "\n\n暂时无法读取网络正文，请稍后重试。"
            }
        }
    }

    @objc private func openComments() {
        navigationController?.pushViewController(CommentsViewController(item: item), animated: true)
    }

    @objc private func openVideo() {
        navigationController?.pushViewController(VideoPlaybackViewController(item: item), animated: true)
    }

    @objc private func primaryAction() {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
            let login = UINavigationController(rootViewController: LoginViewController())
            present(login, animated: true)
            return
        }
        if item.kind == .question {
            let questionID = item.contentID ?? item.questionID ?? 0
            ZhihuActionRepository.shared.follow(questionID: questionID, following: true) { [weak self] result in
                self?.showActionResult(result, success: "已关注这个问题")
            }
        } else if let contentID = item.contentID {
            ZhihuActionRepository.shared.vote(answerID: contentID, up: true) { [weak self] result in
                self?.showActionResult(result, success: "已赞同")
            }
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

    private func actionButton(title: String, image: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = AppTheme.zhihuBlue
        button.setTitleColor(AppTheme.zhihuBlue, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = AppTheme.zhihuBlue.withAlphaComponent(0.08)
        button.layer.cornerRadius = 9
        button.contentEdgeInsets = UIEdgeInsets(top: 11, left: 4, bottom: 11, right: 4)
        return button
    }
}
