import Foundation
import UIKit

enum ZhihuNotificationCategory: String, CaseIterable, Identifiable {
    case comments = "comment"
    case likes = "like"
    case favorites = "favlist_me"
    case follows = "follow"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .comments: return "评论"
        case .likes: return "赞同"
        case .favorites: return "收藏"
        case .follows: return "关注"
        }
    }
    var symbol: String {
        switch self {
        case .comments: return "bubble.left.fill"
        case .likes: return "hand.thumbsup.fill"
        case .favorites: return "bookmark.fill"
        case .follows: return "person.2.fill"
        }
    }
}

struct RemoteNotification: Identifiable {
    let id: String
    let category: ZhihuNotificationCategory
    let title: String
    let detail: String
    let date: String
    let authorName: String?
    let avatarURL: URL?
    let isRead: Bool
    let destinationURL: URL?
}

final class RemoteNotificationRepository {
    static let shared = RemoteNotificationRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func fetch(completion: @escaping (Result<[RemoteNotification], Error>) -> Void) {
        fetch(category: .comments, completion: completion)
    }

    func fetch(category: ZhihuNotificationCategory, completion: @escaping (Result<[RemoteNotification], Error>) -> Void) {
        let url = URL(string: "https://api.zhihu.com/notifications/v3/timeline/entry/\(category.rawValue)?limit=20")!
        client.request(url, headers: Self.mobileHeaders, requiresLogin: true) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do { completion(.success(try Self.decode(data, category: category))) }
                catch { completion(.failure(error)) }
            }
        }
    }

    func markAsRead(category: ZhihuNotificationCategory, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "https://api.zhihu.com/notifications/v3/timeline/entry/\(category.rawValue)/actions/readall")!
        client.request(url, method: "POST", headers: Self.mobileHeaders, requiresLogin: true) { result in
            completion(result.map { _ in () })
        }
    }

    private static func decode(_ data: Data, category: ZhihuNotificationCategory) throws -> [RemoteNotification] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { throw ZhihuSessionError.malformedPayload }
        return rows.compactMap { row in
            let value = (row["value"] as? [String: Any]) ?? row
            let content = value["content"] as? [String: Any]
            let head = value["head"] as? [String: Any]
            let author = head?["author"] as? [String: Any]
            let target = value["target"] as? [String: Any]
            let targetSource = value["target_source"] as? [String: Any]
            let id = string(value["unique_id"]) ?? string(value["id"]) ?? UUID().uuidString
            let title = firstString(content?["title"], value["detail_title"], value["action_text"]) ?? category.title
            let detail = firstString(content?["text"], content?["sub_text"], content?["abstract_text"], targetSource?["text"], targetSource?["full_text"], value["content"], value["detail"]) ?? "你有一条新的知乎消息"
            let avatar = firstString(author?["avatar_url"], head?["avatar_url"], target?["avatar_url"]).flatMap { ZhihuMediaURL.from($0) }
            let targetLink = firstString(content?["target_link"], head?["target_link"], targetSource?["target_link"], target?["url"]).flatMap(URL.init(string:)).flatMap(Self.secureWebURL)
            return RemoteNotification(
                id: id,
                category: category,
                title: plainText(title),
                detail: plainText(detail),
                date: string(value["created_str"]) ?? Self.date(from: value["created"]),
                authorName: firstString(author?["name"], target?["name"]),
                avatarURL: avatar,
                isRead: bool(value["is_read"]) ?? true,
                destinationURL: targetLink
            )
        }
    }

    private static let mobileHeaders = [
        "User-Agent": "com.zhihu.android/Futureve/10.61.0 Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 Chrome/57.0.0.0 Mobile Safari/537.36",
        "x-api-version": "3.1.8",
        "x-app-version": "10.61.0",
        "x-app-za": "OS=Android&Release=12&Product=com.zhihu.android&DeviceType=AndroidPhone"
    ]

    private static func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let string = string(value), !string.isEmpty { return string }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value == "1" || value.lowercased() == "true" }
        return nil
    }

    private static func plainText(_ value: String) -> String {
        guard value.contains("<"), let data = value.data(using: .utf8), let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else { return value }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(from value: Any?) -> String {
        guard let timestamp = value as? NSNumber, timestamp.doubleValue > 0 else { return "刚刚" }
        let date = Date(timeIntervalSince1970: timestamp.doubleValue)
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func secureWebURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), host == "zhihu.com" || host.hasSuffix(".zhihu.com") else { return nil }
        return url
    }
}
