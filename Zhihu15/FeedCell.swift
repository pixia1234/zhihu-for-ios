import UIKit

final class FeedCell: UITableViewCell {
    enum Action: Equatable { case upvote, comment, share }

    var onAction: ((Action) -> Void)?

    private let cardView = UIView()
    private let avatarView = AvatarView()
    private let authorLabel = UILabel()
    private let metaLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let excerptLabel = UILabel()
    private let topicLabel = PillLabel(text: "")
    private let previewView = UIView()
    private let previewImageView = UIImageView()
    private let previewIcon = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled"))
    private let actionsStack = UIStackView()
    private let upvoteButton = FeedCell.makeActionButton(title: "赞同", image: "arrow.up")
    private let commentButton = FeedCell.makeActionButton(title: "评论", image: "bubble.left")
    private let shareButton = FeedCell.makeActionButton(title: "分享", image: "square.and.arrow.up")
    private var previewHeightConstraint: NSLayoutConstraint!
    private var imageURL: URL?
    private var avatarURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onAction = nil
        imageURL = nil
        avatarURL = nil
        previewImageView.image = nil
        previewIcon.isHidden = false
        previewView.isHidden = true
        topicLabel.text = nil
        upvoteButton.setTitle("赞同", for: .normal)
    }

    func configure(with item: FeedItem) {
        avatarView.configure(name: item.author, color: item.avatarColor)
        avatarURL = item.avatarURL
        if let url = item.avatarURL {
            ImagePipeline.shared.image(for: url) { [weak self] image in
                guard let self = self, self.avatarURL == url else { return }
                self.avatarView.setImage(image)
            }
        }
        authorLabel.text = item.author
        metaLabel.text = item.authorRole
        titleLabel.text = item.title
        excerptLabel.text = item.excerpt
        topicLabel.text = item.topic
        previewView.backgroundColor = item.imageColor
        previewView.isHidden = !item.hasImage
        previewHeightConstraint.constant = item.hasImage ? 152 : 0
        imageURL = item.thumbnailURL
        if let url = item.thumbnailURL {
            ImagePipeline.shared.image(for: url) { [weak self] image in
                guard let self = self, self.imageURL == url else { return }
                self.previewImageView.image = image
                self.previewIcon.isHidden = image != nil
            }
        } else {
            previewImageView.image = nil
            previewIcon.isHidden = false
        }
        upvoteButton.setTitle(item.upvotes > 0 ? "\(item.upvotes)" : "赞同", for: .normal)
        commentButton.setTitle(item.comments > 0 ? "\(item.comments)" : "评论", for: .normal)
        let icon = item.kind == .video ? "play.circle.fill" : "photo.on.rectangle.angled"
        previewIcon.image = UIImage(systemName: icon)
        accessibilityLabel = "\(item.kind.rawValue)：\(item.title)"
    }

    private func setupViews() {
        cardView.backgroundColor = AppTheme.card
        cardView.layer.cornerRadius = 12
        cardView.layer.cornerCurve = .continuous
        contentView.addSubview(cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 10, right: 14)
        cardView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cardView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        ])

        let authorRow = UIStackView()
        authorRow.axis = .horizontal
        authorRow.alignment = .center
        authorRow.spacing = 9
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36)
        ])
        authorRow.addArrangedSubview(avatarView)

        let authorInfo = UIStackView()
        authorInfo.axis = .vertical
        authorInfo.spacing = 2
        authorLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = AppTheme.secondaryText
        authorInfo.addArrangedSubview(authorLabel)
        authorInfo.addArrangedSubview(metaLabel)
        authorRow.addArrangedSubview(authorInfo)
        authorRow.addArrangedSubview(UIView())

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = AppTheme.secondaryText
        moreButton.accessibilityLabel = "更多操作"
        authorRow.addArrangedSubview(moreButton)
        stack.addArrangedSubview(authorRow)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = AppTheme.text
        titleLabel.numberOfLines = 3
        stack.addArrangedSubview(titleLabel)

        excerptLabel.font = .systemFont(ofSize: 15)
        excerptLabel.textColor = AppTheme.secondaryText
        excerptLabel.numberOfLines = 3
        stack.addArrangedSubview(excerptLabel)

        previewView.layer.cornerRadius = 8
        previewView.layer.cornerCurve = .continuous
        previewView.clipsToBounds = true
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(previewImageView)
        NSLayoutConstraint.activate([
            previewImageView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: previewView.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor)
        ])
        previewView.addSubview(previewIcon)
        previewIcon.tintColor = AppTheme.zhihuBlue.withAlphaComponent(0.75)
        previewIcon.contentMode = .scaleAspectFit
        previewIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewIcon.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            previewIcon.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            previewIcon.widthAnchor.constraint(equalToConstant: 32),
            previewIcon.heightAnchor.constraint(equalToConstant: 32)
        ])
        previewHeightConstraint = previewView.heightAnchor.constraint(equalToConstant: 0)
        previewHeightConstraint.isActive = true
        stack.addArrangedSubview(previewView)

        let topicActions = UIStackView()
        topicActions.axis = .horizontal
        topicActions.alignment = .center
        topicActions.spacing = 8
        topicActions.addArrangedSubview(topicLabel)
        topicActions.addArrangedSubview(UIView())

        actionsStack.axis = .horizontal
        actionsStack.alignment = .center
        actionsStack.spacing = 2
        actionsStack.addArrangedSubview(upvoteButton)
        actionsStack.addArrangedSubview(commentButton)
        actionsStack.addArrangedSubview(shareButton)
        topicActions.addArrangedSubview(actionsStack)
        stack.addArrangedSubview(topicActions)

        upvoteButton.addTarget(self, action: #selector(upvoteTapped), for: .touchUpInside)
        commentButton.addTarget(self, action: #selector(commentTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
    }

    private static func makeActionButton(title: String, image: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = AppTheme.secondaryText
        button.setTitleColor(AppTheme.secondaryText, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 5, bottom: 6, right: 5)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -2, bottom: 0, right: 3)
        return button
    }

    @objc private func upvoteTapped() { onAction?(.upvote) }
    @objc private func commentTapped() { onAction?(.comment) }
    @objc private func shareTapped() { onAction?(.share) }
}
