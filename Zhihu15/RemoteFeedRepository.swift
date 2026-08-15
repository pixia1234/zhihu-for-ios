import Foundation
import UIKit

enum HomeChannel: Int {
    case recommendation = 0
    case following = 1
    case hot = 2
    case daily = 3
}

struct FeedPage {
    let items: [FeedItem]
    let nextURL: URL?
    let isEnd: Bool
}

final class RemoteFeedRepository {
    static let shared = RemoteFeedRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func fetch(channel: HomeChannel, completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        fetchPage(channel: channel) { result in
            completion(result.map(\.items))
        }
    }

    func fetchPage(channel: HomeChannel, nextURL: URL? = nil, completion: @escaping (Result<FeedPage, Error>) -> Void) {
        switch channel {
        case .recommendation:
            requestFeedPage(nextURL ?? URL(string: "https://api.zhihu.com/topstory/recommend?limit=20")!, requiresLogin: false, completion: completion)
        case .following:
            requestFeedPage(nextURL ?? URL(string: "https://api.zhihu.com/moments_v3?feed_type=recommend&limit=20")!, requiresLogin: true, completion: completion)
        case .hot:
            requestFeedPage(nextURL ?? URL(string: "https://api.zhihu.com/topstory/hot-list?limit=50")!, requiresLogin: false, completion: completion)
        case .daily:
            if nextURL == nil {
                fetchDaily(completion: completion)
            } else {
                completion(.success(FeedPage(items: [], nextURL: nil, isEnd: true)))
            }
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
        requestFeedPage(url, requiresLogin: requiresLogin) { result in
            completion(result.map(\.items))
        }
    }

    private func requestFeedPage(_ url: URL, requiresLogin: Bool, completion: @escaping (Result<FeedPage, Error>) -> Void) {
        client.request(url, requiresLogin: requiresLogin) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do { completion(.success(try Self.decodePage(data))) }
                catch { completion(.failure(error)) }
            }
        }
    }

    private func fetchDaily(completion: @escaping (Result<FeedPage, Error>) -> Void) {
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
                    completion(.success(FeedPage(items: items, nextURL: nil, isEnd: true)))
                } catch { completion(.failure(error)) }
            }
        }
    }

    static func decodeFeed(_ data: Data, defaultKind: FeedItem.Kind? = nil) throws -> [FeedItem] {
        try decodePage(data, defaultKind: defaultKind).items
    }

    static func decodePage(_ data: Data, defaultKind: FeedItem.Kind? = nil) throws -> FeedPage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["data"] as? [[String: Any]] else { throw ZhihuSessionError.malformedPayload }

        var seen = Set<String>()
        let items = values.compactMap { entry -> FeedItem? in
            let target = (entry["target"] as? [String: Any]) ?? (entry["object"] as? [String: Any]) ?? (entry["content"] as? [String: Any]) ?? entry
            guard let rawID = string(target["id"]), !rawID.isEmpty, seen.insert(rawID).inserted else { return nil }
            let type = string(target["type"]) ?? string(entry["type"]) ?? defaultKind?.apiName ?? "question"
            let kind: FeedItem.Kind = type == "article" ? .article : type == "answer" ? .answer : type == "video" || type == "zvideo" ? .video : .question
            let question = target["question"] as? [String: Any]
            let title = string(target["title"]) ?? string(target["name"]) ?? string(question?["title"]) ?? "知乎内容"
            let excerpt = plainText(string(target["excerpt"]) ?? string(target["detail"]) ?? string(target["description"]) ?? "")
            let author = (target["author"] as? [String: Any]) ?? (question?["author"] as? [String: Any])
            let authorName = string(author?["name"]) ?? "知乎用户"
            let avatarURL = ZhihuMediaURL.from(author?["avatar_url"] ?? author?["avatarUrl"] ?? author?["avatar_url_template"])
            let thumbnailURL = Self.mediaURL(from: target)
            let topic = string((target["topic"] as? [String: Any])?["name"]) ?? (kind == .article ? "文章" : kind == .video ? "视频" : "问题")
            let upvotes = int(target["voteup_count"]) ?? int(target["vote_count"]) ?? int(target["like_count"]) ?? 0
            let isVoted = Self.isVoted(target)
            let favoriteCount = int(target["favlists_count"]) ?? int(target["favorite_count"]) ?? 0
            let isFavorited = Self.isFavorited(target)
            let comments = int(target["comment_count"]) ?? 0
            let questionID = (int(question?["id"]) ?? int(target["question_id"]) ?? int(entry["question_id"])).map(Int64.init)
            let fallbackID = Int(UInt64(rawID.hashValue.magnitude) % UInt64(Int.max))
            return FeedItem(id: Int(rawID) ?? fallbackID, kind: kind, author: authorName, authorRole: string(author?["headline"]) ?? "知乎创作者", avatarColor: color(for: rawID), title: plainText(title), excerpt: excerpt.isEmpty ? "打开查看完整内容" : excerpt, topic: topic, upvotes: upvotes, comments: comments, hasImage: thumbnailURL != nil, imageColor: AppTheme.zhihuBlue.withAlphaComponent(0.08), isVoted: isVoted, favoriteCount: favoriteCount, isFavorited: isFavorited, avatarURL: avatarURL, thumbnailURL: thumbnailURL, contentID: Int64(rawID), questionID: questionID)
        }
        let paging = root["paging"] as? [String: Any]
        let nextURL = string(paging?["next"]).flatMap(URL.init(string:))
        let isEnd = bool(paging?["is_end"]) ?? (nextURL == nil)
        return FeedPage(items: items, nextURL: nextURL, isEnd: isEnd)
    }

    private static func mediaURL(from target: [String: Any]) -> URL? {
        var candidates: [Any?] = [
            target["thumbnail_url"], target["thumbnailUrl"], target["thumbnail"],
            target["image_url"], target["imageUrl"], target["cover_url"], target["coverUrl"],
            target["preview_image_url"], target["previewImageUrl"], target["image"], target["cover"]
        ]
        if let info = target["thumbnail_info"] as? [String: Any] {
            candidates.append(contentsOf: [info["url"], info["thumbnail"], info["image_url"]])
            if let thumbnails = info["thumbnails"] as? [[String: Any] ] {
                candidates.append(contentsOf: thumbnails.flatMap { [$0["url"], $0["thumbnail"], $0["image_url"]] })
            }
        }
        if let extra = target["thumbnail_extra_info"] as? [String: Any] {
            candidates.append(contentsOf: [extra["url"], extra["thumbnail"]])
        }
        if let images = target["images"] as? [Any] {
            candidates.append(contentsOf: images)
        }
        candidates.append(target["content"])
        candidates.append(target["detail"])
        if let content = target["content"] as? [[String: Any]] {
            for item in content where string(item["type"]) == "image" || item["url"] != nil || item["image_url"] != nil {
                candidates.append(contentsOf: [item["url"], item["image_url"], item["original_url"], item["thumbnail"]])
            }
        }
        for candidate in candidates {
            if let url = ZhihuMediaURL.from(candidate) { return url }
            if let html = candidate as? String, let url = imageURL(inHTML: html) { return url }
            if let dictionary = candidate as? [String: Any] {
                for key in ["url", "image_url", "imageUrl", "original_url", "thumbnail"] {
                    if let url = ZhihuMediaURL.from(dictionary[key]) { return url }
                }
            }
        }
        return nil
    }

    private static func imageURL(inHTML html: String) -> URL? {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        // Prefer the real lazy-loading source over a 1x1 data URI placeholder.
        for attribute in ["data-actualsrc", "data-original", "data-src", "data-lazy-src", "src"] {
            let pattern = #"(?i)\b"# + attribute + #"\s*=\s*[\"']([^\"']+)[\"']"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: html, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: html) else { continue }
                if let url = ZhihuMediaURL.from(String(html[valueRange]).replacingOccurrences(of: "&amp;", with: "&")) {
                    return url
                }
            }
        }
        return nil
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

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value == "true" || value == "1" }
        return nil
    }

    private static func isVoted(_ target: [String: Any]) -> Bool {
        if let value = bool(target["is_voteup"] ?? target["isVoteup"] ?? target["is_voted"] ?? target["isVoted"]) {
            return value
        }
        let relation = (target["reaction"] as? [String: Any])?["relation"] as? [String: Any]
            ?? target["relationship"] as? [String: Any]
        if int(relation?["voting"]) == 1 { return true }
        return string(relation?["vote"])?.lowercased() == "up"
    }

    private static func isFavorited(_ target: [String: Any]) -> Bool {
        let relation = (target["reaction"] as? [String: Any])?["relation"] as? [String: Any]
            ?? target["relationship"] as? [String: Any]
        return bool(relation?["is_favorited"] ?? relation?["isFavorited"]) ?? false
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

private extension FeedItem.Kind {
    var apiName: String {
        switch self {
        case .question: return "question"
        case .answer: return "answer"
        case .article: return "article"
        case .video: return "video"
        }
    }
}
