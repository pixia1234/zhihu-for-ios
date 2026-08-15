import Foundation

final class ZhihuCreationRepository {
    static let shared = ZhihuCreationRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func saveAnswerDraft(questionID: Int64, html: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "https://www.zhihu.com/api/v4/questions/\(questionID)/draft")!
        let body: [String: Any] = ["content": html, "draft_type": "normal", "delta_time": 30, "settings": ["comment_permission": "all", "table_of_contents_enabled": false]]
        request(url: url, body: body, completion: completion)
    }

    func publishAnswer(questionID: Int64, html: String, completion: @escaping (Result<Int64, Error>) -> Void) {
        saveAnswerDraft(questionID: questionID, html: html) { [weak self] draftResult in
            guard let self = self else { return }
            switch draftResult {
            case let .failure(error): completion(.failure(error))
            case .success:
                let body: [String: Any] = [
                    "action": "answer",
                    "data": [
                        "extra_info": ["question_id": String(questionID), "publisher": "pc"],
                        "hybrid": ["html": html],
                        "draft": ["disabled": 1],
                        "commentsPermission": ["comment_permission": "all"]
                    ]
                ]
                self.request(url: URL(string: "https://www.zhihu.com/api/v4/content/publish")!, body: body) { result in
                    completion(result.flatMap { data in
                        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = Self.int64(root["id"]) ?? Self.int64((root["data"] as? [String: Any])?["id"]) else { return .failure(ZhihuSessionError.malformedPayload) }
                        return .success(id)
                    })
                }
            }
        }
    }

    func publishPin(title: String, text: String, completion: @escaping (Result<Int64, Error>) -> Void) {
        let html = CreationHTMLCompiler.html(from: text)
        let body: [String: Any] = [
            "action": "pin",
            "data": ["title": ["title": title], "hybrid": ["html": html, "textLength": text.count], "draft": ["disabled": 1]]
        ]
        request(url: URL(string: "https://www.zhihu.com/api/v4/content/publish")!, body: body) { result in
            completion(result.flatMap { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = Self.int64(root["id"]) ?? Self.int64((root["data"] as? [String: Any])?["id"]) else { return .failure(ZhihuSessionError.malformedPayload) }
                return .success(id)
            })
        }
    }

    private func request(url: URL, body: [String: Any], completion: @escaping (Result<Data, Error>) -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else { completion(.failure(ZhihuSessionError.malformedPayload)); return }
        client.request(url, method: "POST", body: data, headers: ["Content-Type": "application/json"], requiresLogin: true, completion: completion)
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }
}

enum CreationHTMLCompiler {
    static func html(from text: String) -> String {
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return escaped.split(separator: "\n", omittingEmptySubsequences: false).map { "<p>\($0)</p>" }.joined()
    }
}
