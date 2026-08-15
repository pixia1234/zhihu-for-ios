import UIKit

enum SampleData {
    static let recommendations: [FeedItem] = [
        FeedItem(id: 1, kind: .question, author: "盐选成长计划", authorRole: "知乎盐选 · 编辑推荐", avatarColor: UIColor(red: 0.22, green: 0.47, blue: 0.93, alpha: 1), title: "有哪些看似普通，却能长期改变生活的好习惯？", excerpt: "真正有效的改变往往不需要复杂的计划。把一件小事稳定地做下去，时间会把微小的优势放大。", topic: "生活方式", upvotes: 2840, comments: 186, hasImage: true, imageColor: UIColor(red: 0.86, green: 0.92, blue: 1, alpha: 1)),
        FeedItem(id: 2, kind: .article, author: "吴军", authorRole: "科技作家 · 42 万赞同", avatarColor: UIColor(red: 0.88, green: 0.39, blue: 0.25, alpha: 1), title: "把时间花在真正重要的事情上", excerpt: "我们常常高估一天能做的事，又低估一年能坚持的事。建立自己的节奏，比追赶别人的进度更重要。", topic: "效率", upvotes: 12600, comments: 438, hasImage: false, imageColor: .clear),
        FeedItem(id: 3, kind: .question, author: "林墨", authorRole: "产品经理 · 关注用户体验", avatarColor: UIColor(red: 0.52, green: 0.32, blue: 0.79, alpha: 1), title: "为什么优秀的产品总是让人感觉很简单？", excerpt: "简单不是功能少，而是把复杂留给系统，把清晰留给用户。", topic: "产品", upvotes: 963, comments: 72, hasImage: false, imageColor: .clear),
        FeedItem(id: 4, kind: .video, author: "知学青年", authorRole: "教育 · 课程创作者", avatarColor: UIColor(red: 0.19, green: 0.67, blue: 0.56, alpha: 1), title: "用 10 分钟理解费曼学习法", excerpt: "从输入、复述到反馈，学习可以是一套可重复的流程。", topic: "学习", upvotes: 7380, comments: 205, hasImage: true, imageColor: UIColor(red: 0.86, green: 0.96, blue: 0.92, alpha: 1))
    ]

    static let following: [FeedItem] = [
        FeedItem(id: 5, kind: .article, author: "半佛仙人", authorRole: "商业 · 刚刚发布", avatarColor: UIColor(red: 0.91, green: 0.46, blue: 0.20, alpha: 1), title: "普通人如何建立自己的信息优势？", excerpt: "信息优势不是知道更多，而是更快地找到关键事实，并把它们组织成自己的判断。", topic: "商业思考", upvotes: 521, comments: 31, hasImage: false, imageColor: .clear),
        FeedItem(id: 6, kind: .question, author: "乔纳森", authorRole: "摄影爱好者 · 2 小时前", avatarColor: UIColor(red: 0.15, green: 0.55, blue: 0.75, alpha: 1), title: "拍照时最值得优先考虑的是什么？", excerpt: "先观察光线和主体，再考虑器材。好的照片首先来自清晰的表达。", topic: "摄影", upvotes: 318, comments: 19, hasImage: true, imageColor: UIColor(red: 0.97, green: 0.91, blue: 0.82, alpha: 1))
    ]

    static let daily: [FeedItem] = [
        FeedItem(id: 7, kind: .article, author: "知乎日报", authorRole: "今日精选 · 2026 年 8 月 15 日", avatarColor: UIColor(red: 0.10, green: 0.43, blue: 0.88, alpha: 1), title: "今天值得读的 3 个回答", excerpt: "从城市、科技到个人成长，挑选一些值得慢下来读完的内容。", topic: "日报", upvotes: 18400, comments: 650, hasImage: true, imageColor: UIColor(red: 0.91, green: 0.94, blue: 1, alpha: 1))
    ]

    static let hot: [HotItem] = [
        HotItem(rank: 1, title: "为什么现在的年轻人越来越重视独处？", category: "社会", heat: "982 万热度", summary: "独处不等于孤独，它也可能是恢复能量和整理思绪的方式。"),
        HotItem(rank: 2, title: "有哪些适合普通人的长期主义投资方式？", category: "财经", heat: "756 万热度", summary: "先建立稳定的现金流和风险边界，再谈更远的收益。"),
        HotItem(rank: 3, title: "你是从哪一个瞬间开始喜欢上阅读的？", category: "读书", heat: "643 万热度", summary: "阅读常常从一个具体的人、一句话或一次偶然的相遇开始。"),
        HotItem(rank: 4, title: "人工智能会怎样改变未来五年的工作？", category: "科技", heat: "582 万热度", summary: "工具会改变工作流程，但真正稀缺的判断力与创造力仍然来自人。"),
        HotItem(rank: 5, title: "有哪些低成本却很有幸福感的生活方式？", category: "生活", heat: "516 万热度", summary: "把注意力还给身边的人和事，幸福感往往比想象中更近。"),
        HotItem(rank: 6, title: "如何判断一家公司是否值得长期工作？", category: "职场", heat: "408 万热度", summary: "看业务、看团队，也看自己是否能持续获得成长。")
    ]

    static let messages: [MessageItem] = [
        MessageItem(title: "知乎小管家", detail: "你的回答获得了 24 个赞同", date: "今天", symbol: "bell.fill", color: AppTheme.zhihuBlue),
        MessageItem(title: "林墨", detail: "赞同了你的回答：为什么优秀的产品总是让人感觉很简单？", date: "昨天", symbol: "hand.thumbsup.fill", color: UIColor.systemOrange),
        MessageItem(title: "系统通知", detail: "你关注的话题有了新的优质回答", date: "周三", symbol: "sparkles", color: UIColor.systemPurple)
    ]

    static var allFeedItems: [FeedItem] { recommendations + following + daily }

    static func feedItems(for channel: Int) -> [FeedItem] {
        switch channel {
        case 1: return following
        case 2:
            return hot.enumerated().map { index, item in
                FeedItem(id: 100 + index, kind: .question, author: "知乎热榜", authorRole: item.category + " · " + item.heat, avatarColor: UIColor.systemOrange, title: item.title, excerpt: item.summary, topic: item.category, upvotes: 0, comments: 0, hasImage: false, imageColor: .clear)
            }
        case 3: return daily
        default: return recommendations
        }
    }
}
