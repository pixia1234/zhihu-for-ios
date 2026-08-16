import Foundation
import UIKit

extension Notification.Name {
    static let zhihuHandoffOpenItem = Notification.Name("ZhihuHandoffOpenItem")
    static let zhihuScrollToTop = Notification.Name("ZhihuScrollToTop")
    static let zhihuRefreshHome = Notification.Name("ZhihuRefreshHome")
}

final class HandoffCoordinator {
    static let shared = HandoffCoordinator()

    static let activityType = "com.pixia.zhihu15.client.handoff.content"

    private var currentActivity: NSUserActivity?
    private var currentContentID: Int64?

    private init() {}

    func start(item: FeedItem) {
        guard let contentID = item.contentID, contentID > 0 else { return }
        let activate = { [weak self] in
            guard let self else { return }
            let activity = NSUserActivity(activityType: Self.activityType)
            activity.title = item.title.isEmpty ? "知乎内容" : item.title
            activity.userInfo = [
                "contentID": NSNumber(value: contentID),
                "kind": item.kind.rawValue,
                "id": item.id,
                "title": item.title,
                "excerpt": item.excerpt,
                "topic": item.topic,
                "author": item.author,
                "authorRole": item.authorRole,
                "upvotes": item.upvotes,
                "comments": item.comments,
                "isVoted": item.isVoted,
                "questionID": NSNumber(value: item.questionID ?? 0)
            ]
            activity.webpageURL = RemoteContentRepository.canonicalURLForDisplay(item)
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPublicIndexing = false
            self.currentActivity?.resignCurrent()
            self.currentActivity = activity
            self.currentContentID = contentID
            activity.becomeCurrent()
        }
        if Thread.isMainThread {
            activate()
        } else {
            DispatchQueue.main.async(execute: activate)
        }
    }

    func stop() {
        currentActivity?.resignCurrent()
        currentActivity = nil
        currentContentID = nil
    }

    func stop(item: FeedItem) {
        guard let contentID = item.contentID, contentID == currentContentID else { return }
        stop()
    }

    func handle(_ activity: NSUserActivity) {
        guard activity.activityType == Self.activityType else { return }
        let item = Self.item(from: activity.userInfo)
            ?? Self.item(from: activity.webpageURL, title: activity.title)
        guard let item else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .zhihuHandoffOpenItem, object: item)
        }
    }

    private static func item(from userInfo: [AnyHashable: Any]?) -> FeedItem? {
        guard let userInfo,
              let rawKind = userInfo["kind"] as? String,
              let kind = FeedItem.Kind(rawValue: rawKind),
              let contentID = int64(userInfo["contentID"]),
              contentID > 0 else { return nil }
        let title = string(userInfo["title"]) ?? "知乎内容"
        let questionID = int64(userInfo["questionID"]).flatMap { $0 > 0 ? $0 : nil }
        return FeedItem(
            id: int(userInfo["id"]) ?? Int(contentID),
            kind: kind,
            author: string(userInfo["author"]) ?? "知乎用户",
            authorRole: string(userInfo["authorRole"]) ?? "知乎创作者",
            avatarColor: AppTheme.zhihuBlue,
            title: title,
            excerpt: string(userInfo["excerpt"]) ?? "打开查看完整内容",
            topic: string(userInfo["topic"]) ?? "知乎",
            upvotes: int(userInfo["upvotes"]) ?? 0,
            comments: int(userInfo["comments"]) ?? 0,
            hasImage: false,
            imageColor: AppTheme.zhihuBlue.withAlphaComponent(0.08),
            isVoted: bool(userInfo["isVoted"]) ?? false,
            contentID: contentID,
            questionID: questionID
        )
    }

    private static func item(from url: URL?, title: String?) -> FeedItem? {
        guard let url else { return nil }
        let host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/").map(String.init)
        let fallbackTitle = title?.isEmpty == false ? title! : "知乎内容"

        if host == "zhuanlan.zhihu.com", parts.count >= 2, parts[0] == "p",
           let contentID = Int64(parts[1]), contentID > 0 {
            return makeItem(kind: .article, contentID: contentID, title: fallbackTitle)
        }

        guard host == "www.zhihu.com" || host == "zhihu.com" else { return nil }
        if parts.count >= 4, parts[0] == "question", parts[2] == "answer",
           let questionID = Int64(parts[1]), let answerID = Int64(parts[3]),
           questionID > 0, answerID > 0 {
            return makeItem(kind: .answer, contentID: answerID, title: fallbackTitle, questionID: questionID)
        }
        if parts.count >= 2, parts[0] == "question", let questionID = Int64(parts[1]), questionID > 0 {
            return makeItem(kind: .question, contentID: questionID, title: fallbackTitle)
        }
        if parts.count >= 2, parts[0] == "zvideo", let contentID = Int64(parts[1]), contentID > 0 {
            return makeItem(kind: .video, contentID: contentID, title: fallbackTitle)
        }
        return nil
    }

    private static func makeItem(
        kind: FeedItem.Kind,
        contentID: Int64,
        title: String,
        questionID: Int64? = nil
    ) -> FeedItem {
        FeedItem(
            id: Int(contentID),
            kind: kind,
            author: "知乎用户",
            authorRole: "知乎创作者",
            avatarColor: AppTheme.zhihuBlue,
            title: title,
            excerpt: "打开查看完整内容",
            topic: "知乎",
            upvotes: 0,
            comments: 0,
            hasImage: false,
            imageColor: AppTheme.zhihuBlue.withAlphaComponent(0.08),
            contentID: contentID,
            questionID: questionID
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
