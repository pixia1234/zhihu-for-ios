import UIKit

struct RemoteComment {
    let id: String
    let author: String
    let content: String
    let likeCount: Int
}

final class CommentsViewController: UIViewController {
    private let item: FeedItem
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var comments: [RemoteComment] = []

    init(item: FeedItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "评论"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .compose, target: self, action: #selector(writeComment))
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.register(CommentCell.self, forCellReuseIdentifier: CommentCell.reuseIdentifier)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        loadComments()
    }

    private func loadComments() {
        guard let id = item.contentID else { return }
        let type: String
        switch item.kind { case .answer: type = "answers"; case .article: type = "articles"; case .question: type = "questions"; case .video: type = "zvideos" }
        let url = URL(string: "https://www.zhihu.com/api/v4/comment_v5/\(type)/\(id)/root_comment?limit=20")!
        ZhihuAPIClient.shared.request(url, requiresLogin: false) { [weak self] result in
            guard let self = self, case let .success(data) = result,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = root["data"] as? [[String: Any]] else { return }
            self.comments = values.compactMap { value in
                guard let commentID = Self.string(value["id"]), !commentID.isEmpty else { return nil }
                let author = value["author"] as? [String: Any]
                return RemoteComment(id: commentID, author: Self.string(author?["name"]) ?? "知乎用户", content: Self.plainText(Self.string(value["content"]) ?? ""), likeCount: Self.int(value["like_count"]) ?? 0)
            }
            self.tableView.reloadData()
        }
    }

    @objc private func writeComment() {
        let alert = UIAlertController(title: "发表评论", message: nil, preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "写下你的想法" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "发布", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            ZhihuActionRepository.shared.submitComment(item: self.item, text: text) { result in
                if case .failure = result { return }
                self.loadComments()
            }
        })
        present(alert, animated: true)
    }

    private static func string(_ value: Any?) -> String? { value as? String }
    private static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    private static func plainText(_ html: String) -> String {
        guard html.contains("<"), let data = html.data(using: .utf8), let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else { return html }
        return attributed.string
    }
}

final class CommentCell: UITableViewCell {
    static let reuseIdentifier = "CommentCell"
    private let authorLabel = UILabel()
    private let contentLabel = UILabel()
    private let likeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let stack = UIStackView(arrangedSubviews: [authorLabel, contentLabel, likeLabel])
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
        authorLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        contentLabel.font = .systemFont(ofSize: 15)
        contentLabel.numberOfLines = 0
        likeLabel.font = .systemFont(ofSize: 12)
        likeLabel.textColor = AppTheme.secondaryText
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ comment: RemoteComment) {
        authorLabel.text = comment.author
        contentLabel.text = comment.content
        likeLabel.text = comment.likeCount > 0 ? "\(comment.likeCount) 赞同" : "暂无赞同"
    }
}

extension CommentsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { comments.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CommentCell.reuseIdentifier, for: indexPath) as! CommentCell
        cell.configure(comments[indexPath.row])
        return cell
    }
}

extension CommentsViewController: UITableViewDelegate {}
