import Foundation

struct ZhihuCollectionOption {
    let id: String
    let title: String
    let isSelected: Bool
}

final class ZhihuActionRepository {
    static let shared = ZhihuActionRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func vote(answerID: Int64, up: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "https://www.zhihu.com/api/v4/answers/\(answerID)/voters")!
        let body = try? JSONSerialization.data(withJSONObject: ["type": up ? "up" : "neutral"], options: [])
        client.request(url, method: "POST", body: body, headers: ["Content-Type": "application/json"], requiresLogin: true) { result in completion(result.map { _ in () }) }
    }

    func follow(questionID: Int64, following: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "https://www.zhihu.com/api/v4/questions/\(questionID)/followers")!
        client.request(url, method: following ? "POST" : "DELETE", requiresLogin: true) { result in completion(result.map { _ in () }) }
    }

    func likeComment(commentID: String, liked: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        let encoded = commentID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? commentID
        let url = URL(string: "https://www.zhihu.com/api/v4/comments/\(encoded)/like")!
        client.request(url, method: liked ? "POST" : "DELETE", requiresLogin: true) { result in completion(result.map { _ in () }) }
    }

    func fetchCollections(for item: FeedItem, completion: @escaping (Result<[ZhihuCollectionOption], Error>) -> Void) {
        guard let contentID = item.contentID else {
            completion(.failure(ZhihuSessionError.malformedPayload)); return
        }
        let type: String
        switch item.kind {
        case .answer: type = "answer"
        case .article: type = "article"
        case .question: type = "question"
        case .video: type = "zvideo"
        }
        let url = URL(string: "https://api.zhihu.com/collections/contents/\(type)/\(contentID)?limit=50")!
        client.request(url, requiresLogin: true) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do {
                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let values = root["data"] as? [[String: Any]] else {
                        throw ZhihuSessionError.malformedPayload
                    }
                    let options = values.compactMap { value -> ZhihuCollectionOption? in
                        let collection = (value["value"] as? [String: Any]) ?? value
                        guard let id = Self.string(collection["id"]), !id.isEmpty else { return nil }
                        let title = Self.string(collection["title"]) ?? "未命名收藏夹"
                        let selected = Self.bool(collection["is_favorited"]) ?? Self.bool(collection["isFavorited"]) ?? false
                        return ZhihuCollectionOption(id: id, title: title, isSelected: selected)
                    }
                    completion(.success(options))
                } catch { completion(.failure(error)) }
            }
        }
    }

    func setCollection(_ selected: Bool, collectionID: String, for item: FeedItem, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let contentID = item.contentID,
              !collectionID.isEmpty,
              collectionID.allSatisfy({ $0.isNumber || $0.isLetter || $0 == "-" || $0 == "_" }) else {
            completion(.failure(ZhihuSessionError.malformedPayload)); return
        }
        let type: String
        switch item.kind {
        case .answer: type = "answer"
        case .article: type = "article"
        case .question: type = "question"
        case .video: type = "zvideo"
        }
        let url = URL(string: "https://api.zhihu.com/collections/contents/\(type)/\(contentID)")!
        let key = selected ? "add_collections" : "remove_collections"
        let body = Data("\(key)=\(collectionID)".utf8)
        client.request(url, method: "PUT", body: body, headers: ["Content-Type": "application/x-www-form-urlencoded"], requiresLogin: true) { result in
            completion(result.map { _ in () })
        }
    }

    func submitComment(item: FeedItem, text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let contentID = item.contentID else {
            completion(.failure(ZhihuSessionError.malformedPayload)); return
        }
        let path: String
        switch item.kind {
        case .answer: path = "answers/\(contentID)/comment"
        case .article: path = "articles/\(contentID)/comment"
        case .question: path = "questions/\(contentID)/comment"
        case .video: path = "zvideos/\(contentID)/comment"
        }
        let url = URL(string: "https://www.zhihu.com/api/v4/comment_v5/\(path)")!
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let body = try? JSONSerialization.data(withJSONObject: ["content": "<p>\(escaped)</p>"], options: [])
        client.request(url, method: "POST", body: body, headers: ["Content-Type": "application/json"], requiresLogin: true) { result in completion(result.map { _ in () }) }
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value == "true" || value == "1" }
        return nil
    }
}
