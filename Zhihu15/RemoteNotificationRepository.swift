import Foundation

struct RemoteNotification {
    let title: String
    let detail: String
    let date: String
}

final class RemoteNotificationRepository {
    static let shared = RemoteNotificationRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func fetch(completion: @escaping (Result<[RemoteNotification], Error>) -> Void) {
        let url = URL(string: "https://api.zhihu.com/notifications/v3/message/v3?limit=20")!
        client.request(url, requiresLogin: true) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let values = root["data"] as? [[String: Any]] else {
                    completion(.failure(ZhihuSessionError.malformedPayload)); return
                }
                let rows = values.compactMap { value -> RemoteNotification? in
                    let title = (value["title"] as? String) ?? (value["action_text"] as? String) ?? "知乎通知"
                    let detail = (value["content"] as? String) ?? (value["detail"] as? String) ?? "你有一条新的知乎消息"
                    return RemoteNotification(title: title, detail: detail, date: (value["created_time"] as? String) ?? "刚刚")
                }
                completion(.success(rows))
            }
        }
    }
}
