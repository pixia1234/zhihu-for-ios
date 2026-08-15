import Foundation

final class BrowsingHistoryStore {
    static let shared = BrowsingHistoryStore()
    private let defaults = UserDefaults.standard
    private let key = "zhihu15.browsing-history"
    private let maximumCount = 50

    func record(_ item: FeedItem) {
        var values = storedValues()
        let contentKey = Self.historyKey(for: item)
        values.removeAll { Self.string($0["key"]) == contentKey }
        values.insert(Self.dictionary(for: item, key: contentKey), at: 0)
        defaults.set(Array(values.prefix(maximumCount)), forKey: key)
    }

    func items() -> [FeedItem] {
        storedValues().compactMap(Self.item(from:))
    }

    static func merge(_ remote: [FeedItem], with local: [FeedItem]) -> [FeedItem] {
        var result: [FeedItem] = []
        var seen = Set<String>()
        for item in local + remote {
            let key = historyKey(for: item)
            if seen.insert(key).inserted { result.append(item) }
        }
        return result
    }

    private func storedValues() -> [[String: Any]] {
        (defaults.array(forKey: key) as? [[String: Any]]) ?? []
    }

    private static func dictionary(for item: FeedItem, key: String) -> [String: Any] {
        var result: [String: Any] = [
            "key": key,
            "id": item.id,
            "kind": item.kind.rawValue,
            "author": item.author,
            "authorRole": item.authorRole,
            "title": item.title,
            "excerpt": item.excerpt,
            "topic": item.topic,
            "upvotes": item.upvotes,
            "isVoted": item.isVoted,
            "comments": item.comments,
            "hasImage": item.hasImage
        ]
        if let contentID = item.contentID {
            result["contentID"] = NSNumber(value: contentID)
        }
        if let questionID = item.questionID {
            result["questionID"] = NSNumber(value: questionID)
        }
        if let avatarURL = item.avatarURL?.absoluteString {
            result["avatarURL"] = avatarURL
        }
        if let thumbnailURL = item.thumbnailURL?.absoluteString {
            result["thumbnailURL"] = thumbnailURL
        }
        return result
    }

    private static func historyKey(for item: FeedItem) -> String {
        let identifier = item.contentID.map(String.init) ?? "id:\(item.id)"
        return "\(item.kind.rawValue):\(identifier)"
    }

    private static func item(from value: [String: Any]) -> FeedItem? {
        guard let kindValue = string(value["kind"]), let kind = FeedItem.Kind(rawValue: kindValue),
              let title = string(value["title"]) else { return nil }
        return FeedItem(
            id: int(value["id"]) ?? 0,
            kind: kind,
            author: string(value["author"]) ?? "知乎用户",
            authorRole: string(value["authorRole"]) ?? "知乎创作者",
            avatarColor: AppTheme.zhihuBlue,
            title: title,
            excerpt: string(value["excerpt"]) ?? "打开查看完整内容",
            topic: string(value["topic"]) ?? "知乎",
            upvotes: int(value["upvotes"]) ?? 0,
            comments: int(value["comments"]) ?? 0,
            hasImage: bool(value["hasImage"]) ?? false,
            imageColor: AppTheme.zhihuBlue.withAlphaComponent(0.08),
            isVoted: bool(value["isVoted"]) ?? false,
            avatarURL: string(value["avatarURL"]).flatMap(URL.init(string:)),
            thumbnailURL: string(value["thumbnailURL"]).flatMap(URL.init(string:)),
            contentID: int64(value["contentID"]),
            questionID: int64(value["questionID"])
        )
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value == "true" || value == "1" }
        return nil
    }
}

final class RemoteLibraryRepository {
    static let shared = RemoteLibraryRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func fetchSavedItems(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        guard let account = ZhihuAccountStore.shared.load(),
              let token = account.profile?.urlToken, !token.isEmpty else {
            completion(.failure(ZhihuSessionError.authenticationRequired))
            return
        }
        let listURL = URL(string: "https://www.zhihu.com/api/v4/people/\(token)/collections?limit=10")!
        client.request(listURL, requiresLogin: true) { [weak self] result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let collections = root["data"] as? [[String: Any]],
                      let firstID = collections.first.flatMap({ Self.string($0["id"]) }) else {
                    completion(.success([])); return
                }
                let itemsURL = URL(string: "https://www.zhihu.com/api/v4/collections/\(firstID)/items?limit=20")!
                self?.client.request(itemsURL, requiresLogin: true) { itemResult in
                    switch itemResult {
                    case let .failure(error): completion(.failure(error))
                    case let .success(itemData):
                        do { completion(.success(try RemoteFeedRepository.decodeFeed(itemData))) }
                        catch { completion(.failure(error)) }
                    }
                }
            }
        }
    }

    func fetchHistory(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        let local = BrowsingHistoryStore.shared.items()
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
            completion(.success(local))
            return
        }
        let url = URL(string: "https://api.zhihu.com/unify-consumption/read_history?offset=0&limit=20")!
        client.request(url, requiresLogin: true) { result in
            switch result {
            case .failure: completion(.success(local))
            case let .success(data):
                do {
                    let remote = try RemoteFeedRepository.decodeFeed(data)
                    completion(.success(BrowsingHistoryStore.merge(remote, with: local)))
                } catch { completion(.success(local)) }
            }
        }
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}
