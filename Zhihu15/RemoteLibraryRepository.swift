import Foundation

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
        let url = URL(string: "https://api.zhihu.com/unify-consumption/read_history?offset=0&limit=20")!
        client.request(url, requiresLogin: true) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do { completion(.success(try RemoteFeedRepository.decodeFeed(data))) }
                catch { completion(.failure(error)) }
            }
        }
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}
