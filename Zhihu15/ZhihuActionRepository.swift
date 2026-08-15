import Foundation

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
}
