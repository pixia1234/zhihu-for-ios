import Foundation

struct QuestionAnswersPage {
    let items: [FeedItem]
    let nextURL: URL?
    let isEnd: Bool
}

final class QuestionAnswersRepository {
    static let shared = QuestionAnswersRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func fetch(question: FeedItem, nextURL: URL? = nil, completion: @escaping (Result<QuestionAnswersPage, Error>) -> Void) {
        let questionID = question.contentID ?? question.questionID ?? 0
        guard questionID > 0 else {
            completion(.failure(ZhihuSessionError.malformedPayload))
            return
        }

        let url: URL
        if let nextURL {
            url = nextURL
        } else {
            var components = URLComponents(string: "https://www.zhihu.com/api/v4/questions/\(questionID)/feeds")!
            components.queryItems = [
                URLQueryItem(name: "limit", value: "20"),
                URLQueryItem(name: "order_by", value: "default"),
                URLQueryItem(name: "include", value: "data[*].target.content,data[*].target.author,data[*].target.question,data[*].target.voteup_count,data[*].target.favlists_count,data[*].target.comment_count,data[*].target.relationship,data[*].target.reaction")
            ]
            url = components.url!
        }

        client.request(url, requiresLogin: false) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do {
                    let page = try RemoteFeedRepository.decodePage(data, defaultKind: .answer)
                    let fallbackQuestionID = Int64(questionID)
                    let items = page.items.map { item in
                        FeedItem(
                            id: item.id,
                            kind: .answer,
                            author: item.author,
                            authorRole: item.authorRole,
                            avatarColor: item.avatarColor,
                            title: item.title == "知乎内容" ? question.title : item.title,
                            excerpt: item.excerpt,
                            topic: item.topic == "问题" ? question.topic : item.topic,
                            upvotes: item.upvotes,
                            comments: item.comments,
                            hasImage: item.hasImage,
                            imageColor: item.imageColor,
                            isVoted: item.isVoted,
                            favoriteCount: item.favoriteCount,
                            isFavorited: item.isFavorited,
                            avatarURL: item.avatarURL,
                            thumbnailURL: item.thumbnailURL,
                            contentID: item.contentID,
                            questionID: item.questionID ?? fallbackQuestionID
                        )
                    }
                    completion(.success(QuestionAnswersPage(items: items, nextURL: page.nextURL, isEnd: page.isEnd)))
                } catch { completion(.failure(error)) }
            }
        }
    }
}
