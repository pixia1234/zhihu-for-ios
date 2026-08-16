import Foundation
import UIKit

extension Notification.Name {
    static let zhihuHandoffOpenItem = Notification.Name("ZhihuHandoffOpenItem")
}

final class HandoffCoordinator {
    static let shared = HandoffCoordinator()

    static let activityType = "com.pixia.zhihu15.client.handoff.content"

    private var currentActivity: NSUserActivity?

    private init() {}

    func start(item: FeedItem) {
        guard let contentID = item.contentID, contentID > 0 else { return }
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
        currentActivity?.resignCurrent()
        currentActivity = activity
        activity.becomeCurrent()
    }

    func stop() {
        currentActivity?.resignCurrent()
        currentActivity = nil
    }

    func handle(_ activity: NSUserActivity) {
        guard activity.activityType == Self.activityType,
              let item = Self.item(from: activity.userInfo) else { return }
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
