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
