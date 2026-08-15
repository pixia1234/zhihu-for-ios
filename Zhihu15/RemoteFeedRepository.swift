import Foundation
import UIKit

enum HomeChannel: Int {
    case recommendation = 0
    case following = 1
    case hot = 2
    case daily = 3
}

final class RemoteFeedRepository {
    static let shared = RemoteFeedRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func fetch(channel: HomeChannel, completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        switch channel {
        case .recommendation:
            requestFeed(URL(string: "https://api.zhihu.com/topstory/recommend?limit=20")!, requiresLogin: false, completion: completion)
        case .following:
            requestFeed(URL(string: "https://api.zhihu.com/moments_v3?feed_type=recommend&limit=20")!, requiresLogin: true, completion: completion)
        case .hot:
            requestFeed(URL(string: "https://api.zhihu.com/topstory/hot-list?limit=50")!, requiresLogin: false, completion: completion)
        case .daily:
            fetchDaily(completion: completion)
        }
    }

    func search(query: String, completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        var components = URLComponents(string: "https://www.zhihu.com/api/v4/search_v3")!
        components.queryItems = [
            URLQueryItem(name: "gk_version", value: "gz-gaokao"),
            URLQueryItem(name: "t", value: "general"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "search_source", value: "Normal"),
            URLQueryItem(name: "include", value: "data[*].highlight,object,type")
        ]
        requestFeed(components.url!, requiresLogin: true, completion: completion)
    }

    private func requestFeed(_ url: URL, requiresLogin: Bool, completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        client.request(url, requiresLogin: requiresLogin) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do { completion(.success(try Self.decodeFeed(data))) }
                catch { completion(.failure(error)) }
            }
        }
    }

    private func fetchDaily(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        let url = URL(string: "https://news-at.zhihu.com/api/4/stories/latest")!
        client.request(url) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do {
                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let stories = root["stories"] as? [[String: Any]] else { throw ZhihuSessionError.malformedPayload }
                    let items = stories.compactMap { story -> FeedItem? in
                        guard let id = story["id"] as? Int, let title = story["title"] as? String else { return nil }
                        let imageURL = (story["images"] as? [String])?.first.flatMap(URL.init(string:))
                        return FeedItem(id: id, kind: .article, author: "知乎日报", authorRole: story["hint"] as? String ?? "今日精选", avatarColor: AppTheme.zhihuBlue, title: title, excerpt: "来自知乎日报的每日精选内容", topic: "日报", upvotes: 0, comments: 0, hasImage: imageURL != nil, imageColor: AppTheme.zhihuBlue.withAlphaComponent(0.08), thumbnailURL: imageURL, contentID: Int64(id))
                    }
                    completion(.success(items))
                } catch { completion(.failure(error)) }
            }
        }
    }

    static func decodeFeed(_ data: Data) throws -> [FeedItem] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["data"] as? [[String: Any]] else { throw ZhihuSessionError.malformedPayload }

        var seen = Set<String>()
        return values.compactMap { entry -> FeedItem? in
            let target = (entry["target"] as? [String: Any]) ?? (entry["object"] as? [String: Any]) ?? (entry["content"] as? [String: Any]) ?? entry
            guard let rawID = string(target["id"]), !rawID.isEmpty, seen.insert(rawID).inserted else { return nil }
            let type = string(target["type"]) ?? "question"
            let kind: FeedItem.Kind = type == "article" ? .article : type == "answer" ? .answer : type == "video" || type == "zvideo" ? .video : .question
            let question = target["question"] as? [String: Any]
            let title = string(target["title"]) ?? string(target["name"]) ?? string(question?["title"]) ?? "知乎内容"
            let excerpt = plainText(string(target["excerpt"]) ?? string(target["detail"]) ?? string(target["description"]) ?? "")
            let author = (target["author"] as? [String: Any]) ?? (question?["author"] as? [String: Any])
            let authorName = string(author?["name"]) ?? "知乎用户"
            let avatarURL = (string(author?["avatar_url"]) ?? string(author?["avatarUrl"])).flatMap(URL.init(string:))
            let thumbnailURL = Self.mediaURL(from: target)
            let topic = string((target["topic"] as? [String: Any])?["name"]) ?? (kind == .article ? "文章" : kind == .video ? "视频" : "问题")
            let upvotes = int(target["voteup_count"]) ?? int(target["vote_count"]) ?? int(target["like_count"]) ?? 0
            let comments = int(target["comment_count"]) ?? 0
            let questionID = int(question?["id"]).map(Int64.init)
            let fallbackID = Int(UInt64(rawID.hashValue.magnitude) % UInt64(Int.max))
            return FeedItem(id: Int(rawID) ?? fallbackID, kind: kind, author: authorName, authorRole: string(author?["headline"]) ?? "知乎创作者", avatarColor: color(for: rawID), title: plainText(title), excerpt: excerpt.isEmpty ? "打开查看完整内容" : excerpt, topic: topic, upvotes: upvotes, comments: comments, hasImage: thumbnailURL != nil, imageColor: AppTheme.zhihuBlue.withAlphaComponent(0.08), avatarURL: avatarURL, thumbnailURL: thumbnailURL, contentID: Int64(rawID), questionID: questionID)
        }
    }

    private static func mediaURL(from target: [String: Any]) -> URL? {
        let candidates: [String?] = [
            string(target["thumbnail_url"]), string(target["thumbnailUrl"]), string(target["image_url"]), string(target["imageUrl"]),
            string((target["thumbnail_info"] as? [String: Any])?["url"]), string((target["thumbnail_info"] as? [String: Any])?["thumbnail"])
        ]
        return candidates.compactMap { $0 }.compactMap(URL.init(string:)).first { $0.scheme?.lowercased() == "https" }
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func plainText(_ value: String) -> String {
        guard value.contains("<"), let data = value.data(using: .utf8), let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else { return value }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func color(for value: String) -> UIColor {
        let colors: [UIColor] = [.systemBlue, .systemOrange, .systemPurple, .systemGreen, .systemTeal]
        return colors[abs(value.hashValue) % colors.count]
    }
}
