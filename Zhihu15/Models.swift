import UIKit

struct FeedItem {
    enum Kind: String {
        case question = "问题"
        case answer = "回答"
        case article = "文章"
        case video = "视频"
    }

    let id: Int
    let kind: Kind
    let author: String
    let authorRole: String
    let avatarColor: UIColor
    let title: String
    let excerpt: String
    let topic: String
    let upvotes: Int
    let comments: Int
    let hasImage: Bool
    let imageColor: UIColor
    let avatarURL: URL? = nil
    let thumbnailURL: URL? = nil
    let contentID: Int64? = nil
    let questionID: Int64? = nil

    init(
        id: Int,
        kind: Kind,
        author: String,
        authorRole: String,
        avatarColor: UIColor,
        title: String,
        excerpt: String,
        topic: String,
        upvotes: Int,
        comments: Int,
        hasImage: Bool,
        imageColor: UIColor,
        avatarURL: URL? = nil,
        thumbnailURL: URL? = nil,
        contentID: Int64? = nil,
        questionID: Int64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.author = author
        self.authorRole = authorRole
        self.avatarColor = avatarColor
        self.title = title
        self.excerpt = excerpt
        self.topic = topic
        self.upvotes = upvotes
        self.comments = comments
        self.hasImage = hasImage
        self.imageColor = imageColor
        self.avatarURL = avatarURL
        self.thumbnailURL = thumbnailURL
        self.contentID = contentID
        self.questionID = questionID
    }
}

struct HotItem {
    let rank: Int
    let title: String
    let category: String
    let heat: String
    let summary: String
}

struct MessageItem {
    let title: String
    let detail: String
    let date: String
    let symbol: String
    let color: UIColor
}
