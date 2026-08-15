import Foundation

enum ProfileContentTab: String, CaseIterable, Identifiable {
    case answers
    case articles
    case questions

    var id: String { rawValue }
    var title: String {
        switch self {
        case .answers: return "回答"
        case .articles: return "文章"
        case .questions: return "问题"
        }
    }

    var defaultKind: FeedItem.Kind {
        switch self {
        case .answers: return .answer
        case .articles: return .article
        case .questions: return .question
        }
    }
}

struct RemotePersonProfile {
    let id: String
    let urlToken: String?
    let name: String
    let headline: String
    let avatarURL: URL?
    let answerCount: Int
    let articleCount: Int
    let questionCount: Int
    let followerCount: Int
    let followingCount: Int
}

final class RemoteProfileRepository {
    static let shared = RemoteProfileRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func fetchProfile(completion: @escaping (Result<RemotePersonProfile, Error>) -> Void) {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
            completion(.failure(ZhihuSessionError.authenticationRequired)); return
        }
        let token = ZhihuAccountStore.shared.load()?.profile?.urlToken
        let path = token.flatMap { $0.isEmpty ? nil : $0 } ?? "me"
        let url = URL(string: "https://api.zhihu.com/people/\(path)?include=allow_message,is_followed,is_following,is_org,is_blocking,badge_v2,answer_count,follower_count,following_count,articles_count,question_count,pins_count")!
        client.request(url, requiresLogin: true) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do {
                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ZhihuSessionError.malformedPayload }
                    let id = Self.string(root["id"]) ?? ""
                    guard !id.isEmpty else { throw ZhihuSessionError.malformedPayload }
                    completion(.success(RemotePersonProfile(
                        id: id,
                        urlToken: Self.string(root["url_token"]) ?? Self.string(root["urlToken"]),
                        name: Self.string(root["name"]) ?? "知乎用户",
                        headline: Self.string(root["headline"]) ?? "",
                        avatarURL: ZhihuMediaURL.from(root["avatar_url"] ?? root["avatarUrl"]),
                        answerCount: Self.int(root["answer_count"]),
                        articleCount: Self.int(root["articles_count"]),
                        questionCount: Self.int(root["question_count"]),
                        followerCount: Self.int(root["follower_count"]),
                        followingCount: Self.int(root["following_count"])
                    )))
                } catch { completion(.failure(error)) }
            }
        }
    }

    func fetchContent(tab: ProfileContentTab, completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        guard let token = ZhihuAccountStore.shared.load()?.profile?.urlToken, !token.isEmpty else {
            completion(.failure(ZhihuSessionError.authenticationRequired)); return
        }
        let endpoint: String
        switch tab {
        case .answers: endpoint = "https://www.zhihu.com/api/v4/members/\(Self.path(token))/answers"
        case .articles: endpoint = "https://www.zhihu.com/api/v4/members/\(Self.path(token))/articles"
        case .questions: endpoint = "https://www.zhihu.com/api/v4/members/\(Self.path(token))/questions"
        }
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "offset", value: "0")
        ]
        client.request(components.url!, requiresLogin: true) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do { completion(.success(try RemoteFeedRepository.decodeFeed(data, defaultKind: tab.defaultKind))) }
                catch { completion(.failure(error)) }
            }
        }
    }

    private static func path(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }
}
