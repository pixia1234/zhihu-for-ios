import Foundation

struct RemoteContent {
    let title: String
    let body: String
    let bodyHTML: String
    let author: String?
    let authorHeadline: String?
    let imageURL: URL?
    let canonicalURL: URL?
}

final class RemoteContentRepository {
    static let shared = RemoteContentRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func fetch(item: FeedItem, completion: @escaping (Result<RemoteContent, Error>) -> Void) {
        guard let contentID = item.contentID else {
            completion(.failure(ZhihuSessionError.malformedPayload))
            return
        }
        let url: URL
        switch item.kind {
        case .answer:
            url = URL(string: "https://www.zhihu.com/api/v4/answers/\(contentID)?include=content,author,question,voteup_count,comment_count")!
        case .question:
            url = URL(string: "https://www.zhihu.com/api/v4/questions/\(contentID)?include=detail,author,answer_count,follower_count")!
        case .article:
            url = URL(string: "https://zhuanlan.zhihu.com/api/articles/\(contentID)")!
        case .video:
            completion(.success(RemoteContent(title: item.title, body: item.excerpt, bodyHTML: item.excerpt, author: item.author, authorHeadline: item.authorRole, imageURL: item.thumbnailURL, canonicalURL: Self.canonicalURLForDisplay(item))))
            return
        }
        client.request(url, requiresLogin: false) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do { completion(.success(try Self.decode(data, fallback: item))) }
                catch { completion(.failure(error)) }
            }
        }
    }

    private static func decode(_ data: Data, fallback: FeedItem) throws -> RemoteContent {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ZhihuSessionError.malformedPayload }
        let title = string(root["title"]) ?? string((root["question"] as? [String: Any])?["title"]) ?? fallback.title
        let bodyHTML = string(root["content_html"]) ?? string(root["contentHtml"]) ?? string(root["content"]) ?? string(root["detail"]) ?? string(root["description"]) ?? fallback.excerpt
        let body = plainText(bodyHTML)
        let author = root["author"] as? [String: Any]
        let authorName = string(author?["name"]) ?? fallback.author
        let headline = string(author?["headline"]) ?? fallback.authorRole
        let image = ZhihuMediaURL.from(root["image_url"] ?? root["imageUrl"]) ?? fallback.thumbnailURL
        let canonicalURL = (string(root["url"]) ?? string(root["url_token"])).flatMap(URL.init(string:)) ?? Self.canonicalURLForDisplay(fallback)
        return RemoteContent(title: plainText(title), body: body, bodyHTML: bodyHTML, author: authorName, authorHeadline: headline, imageURL: image, canonicalURL: canonicalURL)
    }

    private static func string(_ value: Any?) -> String? { value as? String }

    private static func plainText(_ html: String) -> String {
        guard html.contains("<"), let data = html.data(using: .utf8), let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else { return html.trimmingCharacters(in: .whitespacesAndNewlines) }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalURLForDisplay(_ item: FeedItem) -> URL? {
        guard let id = item.contentID else { return nil }
        switch item.kind {
        case .answer:
            if let questionID = item.questionID { return URL(string: "https://www.zhihu.com/question/\(questionID)/answer/\(id)") }
            return URL(string: "https://www.zhihu.com/question/0/answer/\(id)")
        case .question: return URL(string: "https://www.zhihu.com/question/\(id)")
        case .article: return URL(string: "https://zhuanlan.zhihu.com/p/\(id)")
        case .video: return URL(string: "https://www.zhihu.com/zvideo/\(id)")
        }
    }
}
