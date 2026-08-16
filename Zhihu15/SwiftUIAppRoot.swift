import SwiftUI
import UIKit

struct SwiftUIAppRootView: View {
    @State private var selectedTab = 0
    @State private var detailRoute: SwiftUIDetailRoute?

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                SwiftUIHomeView()
                    .tabItem { Label("首页", systemImage: "house") }
                    .tag(0)

                SwiftUICollectionView()
                    .tabItem { Label("收藏", systemImage: "bookmark") }
                    .tag(1)

                SwiftUIProfileView()
                    .tabItem { Label("我的", systemImage: "person.crop.circle") }
                    .tag(2)
            }
            .accentColor(Color(red: 0.08, green: 0.38, blue: 0.86))
            .background(SwiftUIHandoffDetailLink(route: $detailRoute))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onReceive(NotificationCenter.default.publisher(for: .zhihuHandoffOpenItem)) { notification in
            selectedTab = 0
            if let item = notification.object as? FeedItem {
                detailRoute = SwiftUIDetailRoute(item: item)
            }
        }
    }
}

final class SwiftUIFeedStore: ObservableObject {
    @Published var channel: HomeChannel = .recommendation
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var canLoadMore = false
    @Published var errorMessage: String?
    private var nextPageURL: URL?

    func load(channel: HomeChannel? = nil) {
        let requested = channel ?? self.channel
        self.channel = requested
        guard !isLoading, !isLoadingMore else { return }
        isLoading = true
        hasLoaded = false
        nextPageURL = nil
        canLoadMore = false
        errorMessage = nil
        RemoteFeedRepository.shared.fetchPage(channel: requested) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.hasLoaded = true
            switch result {
            case let .success(page):
                self.items = page.items
                self.nextPageURL = page.nextURL
                self.canLoadMore = !page.isEnd && page.nextURL != nil
            case let .failure(error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func refresh() async {
        await withCheckedContinuation { continuation in
            guard !isLoading, !isLoadingMore else {
                continuation.resume()
                return
            }
            let requested = channel
            isLoading = true
            nextPageURL = nil
            canLoadMore = false
            RemoteFeedRepository.shared.fetchPage(channel: requested) { [weak self] result in
                guard let self = self else { continuation.resume(); return }
                self.isLoading = false
                self.hasLoaded = true
                switch result {
                case let .success(page):
                    self.items = page.items
                    self.nextPageURL = page.nextURL
                    self.canLoadMore = !page.isEnd && page.nextURL != nil
                    self.errorMessage = nil
                case let .failure(error):
                    self.errorMessage = error.localizedDescription
                }
                continuation.resume()
            }
        }
    }

    func loadMore() {
        guard hasLoaded, canLoadMore, !isLoading, !isLoadingMore, let nextPageURL else { return }
        isLoadingMore = true
        RemoteFeedRepository.shared.fetchPage(channel: channel, nextURL: nextPageURL) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingMore = false
            switch result {
            case let .success(page):
                let existingIDs = Set(self.items.map(\.id))
                self.items.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
                self.nextPageURL = page.nextURL
                self.canLoadMore = !page.isEnd && page.nextURL != nil
            case let .failure(error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func vote(item: FeedItem, completion: @escaping (Result<ZhihuVoteMutation, Error>) -> Void) {
        guard item.kind != .question, let contentID = item.contentID, contentID > 0 else {
            completion(.failure(ZhihuSessionError.malformedPayload))
            return
        }
        let requestedVote = !item.isVoted
        ZhihuActionRepository.shared.vote(contentID: contentID, kind: item.kind, up: requestedVote) { [weak self] result in
            guard let self = self else { return }
            if case let .success(mutation) = result,
               let index = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[index].isVoted = mutation.isVoted
                if let serverCount = mutation.upvoteCount {
                    self.items[index].upvotes = max(0, serverCount)
                } else {
                    self.items[index].upvotes = max(0, self.items[index].upvotes + (mutation.isVoted ? 1 : -1))
                }
            }
            completion(result)
        }
    }
}

struct SwiftUIHomeView: View {
    @StateObject private var store = SwiftUIFeedStore()
    @State private var showMessages = false
    @State private var showCreation = false
    @State private var showSearch = false
    @State private var showLogin = false
    @State private var actionMessage: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let autoRefreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                if let error = store.errorMessage, store.items.isEmpty {
                    SwiftUIErrorCard(message: error) { store.load() }
                }
                if store.isLoading && store.items.isEmpty {
                    ProgressView("正在加载知乎内容").frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                ForEach(store.items, id: \.id) { item in
                    SwiftUIFeedCardLink(
                        item: item,
                        onVote: {
                            store.vote(item: item) { result in
                                switch result {
                                case .success:
                                    actionMessage = item.isVoted ? "已取消赞同" : "已赞同"
                                case let .failure(error):
                                    if let sessionError = error as? ZhihuSessionError,
                                       case .authenticationRequired = sessionError {
                                        showLogin = true
                                    } else {
                                        actionMessage = error.localizedDescription
                                    }
                                }
                            }
                        }
                    )
                    .onAppear {
                        if item.id == store.items.last?.id { store.loadMore() }
                    }
                }
                if store.isLoadingMore {
                    ProgressView("正在加载更多").frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                if !store.isLoading && store.items.isEmpty && store.errorMessage == nil {
                    SwiftUIEmptyState(title: "暂时没有内容", systemImage: "tray")
                }
            }
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 14)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .refreshable { await store.refresh() }
        .navigationTitle("知乎")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("搜索")
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.isLoading)
                    .accessibilityLabel("刷新")
                Button { showCreation = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("开始创作")
                Button { showMessages = true } label: { Image(systemName: "bell") }
                    .accessibilityLabel("知乎消息")
            }
        }
        .onAppear {
            if !store.hasLoaded { store.load() }
        }
        .onReceive(autoRefreshTimer) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refresh() }
        }
        .sheet(isPresented: $showMessages) {
            UIKitNavigationScreen { MessagesViewController() }
        }
        .sheet(isPresented: $showCreation) {
            UIKitNavigationScreen { RichTextEditorViewController(mode: .pin) }
        }
        .sheet(isPresented: $showSearch) {
            UIKitNavigationScreen { SearchViewController() }
        }
        .sheet(isPresented: $showLogin) {
            UIKitNavigationScreen { LoginViewController() }
        }
        .alert("知乎", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("好的", role: .cancel) { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("内容频道", selection: Binding(get: { store.channel.rawValue }, set: { store.load(channel: HomeChannel(rawValue: $0) ?? .recommendation) })) {
                Text("推荐").tag(0); Text("关注").tag(1); Text("热榜").tag(2); Text("日报").tag(3)
            }
            .pickerStyle(.segmented)
        }
    }
}

struct SwiftUIFeedCard: View {
    let item: FeedItem
    var onVote: (() -> Void)? = nil
    var onComment: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CachedAvatar(url: item.avatarURL, name: item.author, color: item.avatarColor, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.author).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(item.authorRole).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Text(item.kind.rawValue).font(.caption.weight(.medium)).foregroundColor(Color(red: 0.08, green: 0.38, blue: 0.86))
            }
            Text(item.title).font(.headline).foregroundColor(.primary).multilineTextAlignment(.leading).lineLimit(4)
            if !item.excerpt.isEmpty { Text(item.excerpt).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.leading).lineLimit(4) }
            if let thumbnailURL = item.thumbnailURL {
                CachedRemoteImage(url: thumbnailURL)
                    .frame(maxWidth: .infinity).frame(height: 174)
                    .background(Color(uiColor: item.imageColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 16) {
                if let onVote = onVote {
                    Button(action: onVote) {
                        Label(item.isVoted ? "已赞同" : (item.upvotes > 0 ? "\(item.upvotes)" : "赞同"), systemImage: item.isVoted ? "arrow.up.circle.fill" : "arrow.up")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Label(item.isVoted ? "已赞同" : (item.upvotes > 0 ? "\(item.upvotes)" : "赞同"), systemImage: item.isVoted ? "arrow.up.circle.fill" : "arrow.up")
                }
                if let onComment = onComment {
                    Button(action: onComment) {
                        Label(item.comments > 0 ? "\(item.comments)" : "评论", systemImage: "bubble.left")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Label(item.comments > 0 ? "\(item.comments)" : "评论", systemImage: "bubble.left")
                }
                if let onShare = onShare {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("分享")
                }
                Spacer()
                Text(item.topic).font(.caption).foregroundColor(Color(red: 0.08, green: 0.38, blue: 0.86))
            }
            .font(.caption.weight(.medium)).foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.16)))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The normal content path uses a real NavigationLink. A hidden, shared
/// NavigationLink is reserved for external Handoff events only; using it for
/// every card makes SwiftUI reuse the destination toolbar across pushes.
struct SwiftUIFeedCardLink: View {
    let item: FeedItem
    var onVote: (() -> Void)? = nil
    var onComment: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    var body: some View {
        NavigationLink(destination: SwiftUIDetailDestinationView(item: item)) {
            SwiftUIFeedCard(item: item, onVote: onVote, onComment: onComment, onShare: onShare)
        }
        .buttonStyle(.plain)
    }
}

/// Every in-app and external navigation path resolves to this one detail
/// destination. Keeping the destination in one view prevents SwiftUI from
/// creating subtly different toolbar/safe-area hierarchies for cards and
/// Handoff.
struct SwiftUIDetailDestinationView: View {
    let item: FeedItem

    var body: some View {
        SwiftUIDetailView(item: item)
    }
}

struct SwiftUIDetailRoute: Identifiable { let id = UUID(); let item: FeedItem }

final class SwiftUIDetailStore: ObservableObject {
    let item: FeedItem
    @Published private(set) var content: RemoteContent?
    @Published private(set) var isLoading = false
    @Published private(set) var collectionOptions: [ZhihuCollectionOption] = []
    @Published private(set) var isLoadingCollections = false
    @Published var upvotes: Int
    @Published var isVoted: Bool
    @Published var favoriteCount: Int
    @Published var isFavorited: Bool
    @Published var actionMessage: String?

    private var didLoad = false
    private var hasRemoteFavoriteCount = false

    init(item: FeedItem) {
        self.item = item
        self.upvotes = item.upvotes
        self.isVoted = item.isVoted
        self.favoriteCount = item.favoriteCount
        self.isFavorited = item.isFavorited
    }

    var title: String { content?.title ?? item.title }
    var author: String { content?.author ?? item.author }
    var authorHeadline: String { content?.authorHeadline ?? item.authorRole }
    var bodyMarkup: String {
        guard let markup = content?.bodyHTML, !markup.isEmpty else { return item.excerpt }
        return markup
    }
    var imageURL: URL? { content?.imageURL ?? item.thumbnailURL }
    var canonicalURL: URL? { content?.canonicalURL ?? RemoteContentRepository.canonicalURLForDisplay(item) }
    var comments: Int { max(0, item.comments) }

    func load() {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        RemoteContentRepository.shared.fetch(item: item) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            if case let .success(content) = result {
                self.content = content
                if let value = content.upvoteCount { self.upvotes = max(0, value) }
                if let value = content.isVoted { self.isVoted = value }
                if let value = content.favoriteCount {
                    self.favoriteCount = max(0, value)
                    self.hasRemoteFavoriteCount = true
                }
                if let value = content.isFavorited { self.isFavorited = value }
            } else if case let .failure(error) = result {
                self.actionMessage = error.localizedDescription
            }
            self.loadCollections()
        }
    }

    func loadCollections() {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true,
              item.contentID != nil,
              !isLoadingCollections else { return }
        isLoadingCollections = true
        ZhihuActionRepository.shared.fetchCollections(for: item) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingCollections = false
            guard case let .success(options) = result else { return }
            self.collectionOptions = options
            self.isFavorited = options.contains(where: \.isSelected)
            if !self.hasRemoteFavoriteCount {
                self.favoriteCount = options.filter(\.isSelected).count
            }
        }
    }

    func vote(completion: @escaping (Result<Void, Error>) -> Void) {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
            completion(.failure(ZhihuSessionError.authenticationRequired))
            return
        }
        guard let contentID = item.contentID, contentID > 0, item.kind != .question else {
            completion(.failure(ZhihuSessionError.malformedPayload))
            return
        }
        let requested = !isVoted
        ZhihuActionRepository.shared.vote(contentID: contentID, kind: item.kind, up: requested) { [weak self] result in
            guard let self = self else { return }
            if case let .success(mutation) = result {
                self.isVoted = mutation.isVoted
                if let count = mutation.upvoteCount {
                    self.upvotes = max(0, count)
                } else {
                    self.upvotes = max(0, self.upvotes + (mutation.isVoted ? 1 : -1))
                }
            }
            completion(result.map { _ in () })
        }
    }

    func follow(completion: @escaping (Result<Void, Error>) -> Void) {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
            completion(.failure(ZhihuSessionError.authenticationRequired))
            return
        }
        let questionID = item.contentID ?? item.questionID ?? 0
        guard questionID > 0 else {
            completion(.failure(ZhihuSessionError.malformedPayload))
            return
        }
        ZhihuActionRepository.shared.follow(questionID: questionID, following: true, completion: completion)
    }

    func setCollection(_ option: ZhihuCollectionOption, selected: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        ZhihuActionRepository.shared.setCollection(selected, collectionID: option.id, for: item) { [weak self] result in
            guard let self = self else { return }
            if case .success = result {
                self.collectionOptions = self.collectionOptions.map {
                    ZhihuCollectionOption(id: $0.id, title: $0.title, isSelected: $0.id == option.id ? selected : $0.isSelected)
                }
                self.isFavorited = self.collectionOptions.contains(where: \.isSelected)
                if !self.hasRemoteFavoriteCount {
                    self.favoriteCount = self.collectionOptions.filter(\.isSelected).count
                } else {
                    self.favoriteCount = max(0, self.favoriteCount + (selected ? 1 : -1))
                }
            }
            completion(result)
        }
    }
}

struct SwiftUIHandoffDetailLink: View {
    @Binding var route: SwiftUIDetailRoute?

    var body: some View {
        NavigationLink(
            destination: destination,
            isActive: Binding(
                get: { route != nil },
                set: { isActive in
                    if !isActive {
                        route = nil
                    }
                }
            )
        ) {
            EmptyView()
        }
        .hidden()
    }

    @ViewBuilder
    private var destination: some View {
        if let route = route {
            SwiftUIDetailDestinationView(item: route.item)
        } else {
            EmptyView()
        }
    }
}

struct SwiftUIDetailView: View {
    let item: FeedItem
    @StateObject private var store: SwiftUIDetailStore
    @State private var richContentHeight: CGFloat = 28
    @State private var showLogin = false
    @State private var showComments = false
    @State private var showCollectionPicker = false
    @State private var showVideo = false
    @State private var showWebContent = false
    @State private var webURL: URL?

    init(item: FeedItem) {
        self.item = item
        _store = StateObject(wrappedValue: SwiftUIDetailStore(item: item))
    }

    var body: some View {
        detailScrollView
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        // The system bottom bar is a UIToolbar owned by the navigation
        // controller: on iOS 15 it is shown/hidden separately from the page,
        // so it does not slide in parallel during push/pop, and it can render
        // without the material. Drawing the bar inside the page keeps both the
        // transition and the blur consistent across iOS 15/16.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            detailBottomBar
        }
        .navigationTitle(store.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if item.kind == .video {
                    Button { showVideo = true } label: { Image(systemName: "play.circle") }
                        .accessibilityLabel("播放")
                }
                Button {
                    if let url = store.canonicalURL { openInBrowser(url) }
                } label: { Image(systemName: "safari") }
                    .accessibilityLabel("在浏览器打开本回答")
                    .help("在浏览器打开本回答")
            }
        }
        .onAppear {
            store.load()
            AppTheme.refreshLiveAppearance()
            DispatchQueue.main.async {
                AppTheme.refreshLiveAppearance()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                AppTheme.refreshLiveAppearance()
            }
        }
        .alert(isPresented: Binding(
            get: { store.actionMessage != nil },
            set: { if !$0 { store.actionMessage = nil } }
        )) {
            Alert(title: Text("知乎"), message: Text(store.actionMessage ?? ""), dismissButton: .default(Text("好的")))
        }
        .sheet(isPresented: $showLogin) { UIKitNavigationScreen { LoginViewController() } }
        .sheet(isPresented: $showComments) { UIKitNavigationScreen { CommentsViewController(item: item) } }
        .sheet(isPresented: $showVideo) { UIKitNavigationScreen { VideoPlaybackViewController(item: item) } }
        .sheet(isPresented: $showWebContent) {
            if let webURL = webURL {
                UIKitNavigationScreen { WebContentViewController(url: webURL, title: "知乎内容") }
            }
        }
        .sheet(isPresented: $showCollectionPicker) { collectionPicker }
    }

    @ViewBuilder
    private var answersDestination: some View {
        if let question = answersQuestion {
            SwiftUIAnswersView(
                question: question,
                excludingAnswerID: item.kind == .answer ? item.contentID : nil
            )
        } else {
            SwiftUIEmptyState(title: "缺少问题 ID", systemImage: "questionmark.circle")
        }
    }

    private var detailScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                authorHeader
                Text(store.title)
                    .font(.system(size: 25, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                if let imageURL = store.imageURL {
                    CachedRemoteImage(url: imageURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .background(Color(uiColor: item.imageColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                SwiftUIRichContentView(markup: store.bodyMarkup, height: $richContentHeight) { url in
                    openContentURL(url)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: richContentHeight, alignment: .top)
                Divider()
                if item.kind == .question {
                    answersAction(title: "查看全部回答")
                } else if item.kind == .answer, item.questionID != nil {
                    answersAction(title: "继续查看下一个回答")
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func answersAction(title: String) -> some View {
        if answersQuestion != nil {
            NavigationLink(destination: answersDestination) {
                answersLabel(title: title)
            }
        } else {
            Button {
                store.actionMessage = "缺少问题 ID，暂时无法加载全部回答"
            } label: {
                answersLabel(title: title)
            }
        }
    }

    private func answersLabel(title: String) -> some View {
        Label(title, systemImage: "chevron.right")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .foregroundColor(Color(red: 0.08, green: 0.38, blue: 0.86))
    }

    private var answersQuestion: FeedItem? {
        guard item.kind == .answer else {
            guard let contentID = item.contentID ?? item.questionID, contentID > 0 else { return nil }
            return item
        }
        guard let questionID = item.questionID, questionID > 0 else { return nil }
        return FeedItem(
            id: Int(questionID),
            kind: .question,
            author: "知乎问题",
            authorRole: "",
            avatarColor: AppTheme.zhihuBlue,
            title: store.title,
            excerpt: "",
            topic: item.topic,
            upvotes: 0,
            comments: 0,
            hasImage: false,
            imageColor: AppTheme.zhihuBlue.withAlphaComponent(0.08),
            contentID: questionID
        )
    }

    private var authorHeader: some View {
        HStack(spacing: 10) {
            CachedAvatar(url: item.avatarURL, name: store.author, color: item.avatarColor, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.author).font(.headline)
                Text(store.authorHeadline).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
            }
            Spacer()
        }
    }

    private var detailVoteToolbarButton: some View {
        Button {
            if ZhihuAccountStore.shared.load()?.isLoggedIn != true {
                showLogin = true
            } else if item.kind == .question {
                store.follow { result in
                    switch result {
                    case .success:
                        store.actionMessage = "已关注这个问题"
                    case let .failure(error):
                        store.actionMessage = error.localizedDescription
                    }
                }
            } else {
                store.vote { result in
                    if case let .failure(error) = result {
                        if let sessionError = error as? ZhihuSessionError,
                           case .authenticationRequired = sessionError {
                            showLogin = true
                        } else {
                            store.actionMessage = error.localizedDescription
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: item.kind == .question ? "person.badge.plus" : (store.isVoted ? "arrow.up.circle.fill" : "arrow.up"))
                if item.kind != .question {
                    Text("\(max(0, store.upvotes))")
                }
            }
        }
        .accessibilityLabel(item.kind == .question ? "关注问题" : "赞同，\(max(0, store.upvotes))")
    }

    private var detailCommentsToolbarButton: some View {
        Button { showComments = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                Text("\(store.comments)")
            }
        }
        .accessibilityLabel("评论，\(store.comments)")
    }

    private var detailCollectionToolbarButton: some View {
        Button {
            if ZhihuAccountStore.shared.load()?.isLoggedIn != true {
                showLogin = true
            } else {
                store.loadCollections()
                showCollectionPicker = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.isFavorited ? "bookmark.fill" : "bookmark")
                Text("\(max(0, store.favoriteCount))")
            }
        }
        .accessibilityLabel("收藏，\(max(0, store.favoriteCount))")
    }

    private var detailBottomBar: some View {
        HStack(spacing: 0) {
            detailVoteToolbarButton
            Spacer()
            detailCommentsToolbarButton
            Spacer()
            detailCollectionToolbarButton
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var collectionPicker: some View {
        NavigationView {
            Group {
                if store.isLoadingCollections && store.collectionOptions.isEmpty {
                    ProgressView("正在加载收藏夹").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.collectionOptions.isEmpty {
                    SwiftUIEmptyState(title: "暂无可用收藏夹", systemImage: "bookmark")
                } else {
                    List {
                        ForEach(store.collectionOptions, id: \.id) { option in
                            Button {
                                store.setCollection(option, selected: !option.isSelected) { result in
                                    if case let .failure(error) = result { store.actionMessage = error.localizedDescription }
                                }
                            } label: {
                                HStack {
                                    Text(option.title).foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(option.isSelected ? Color(red: 0.08, green: 0.38, blue: 0.86) : .secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("收藏到")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { showCollectionPicker = false } } }
        }
    }

    private func openContentURL(_ url: URL) {
        guard url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" else { return }
        if url.host?.lowercased().hasSuffix("zhihu.com") == true {
            webURL = url
            showWebContent = true
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func openInBrowser(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        UIApplication.shared.open(url, options: [:])
    }
}

final class SwiftUIAnswersStore: ObservableObject {
    let question: FeedItem
    let excludingAnswerID: Int64?

    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private var nextPageURL: URL?

    init(question: FeedItem, excludingAnswerID: Int64?) {
        self.question = question
        self.excludingAnswerID = excludingAnswerID
    }

    func load() {
        guard !isLoading, !isLoadingMore else { return }
        isLoading = true
        hasLoaded = false
        nextPageURL = nil
        errorMessage = nil
        QuestionAnswersRepository.shared.fetch(question: question) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.hasLoaded = true
            switch result {
            case let .success(page):
                self.items = page.items.filter { $0.contentID != self.excludingAnswerID }
                self.nextPageURL = page.nextURL
                if self.items.isEmpty, page.nextURL != nil { self.loadMore() }
            case let .failure(error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func refresh() async {
        await withCheckedContinuation { continuation in
            guard !isLoading, !isLoadingMore else {
                continuation.resume()
                return
            }
            isLoading = true
            nextPageURL = nil
            errorMessage = nil
            QuestionAnswersRepository.shared.fetch(question: question) { [weak self] result in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                self.isLoading = false
                self.hasLoaded = true
                switch result {
                case let .success(page):
                    self.items = page.items.filter { $0.contentID != self.excludingAnswerID }
                    self.nextPageURL = page.nextURL
                case let .failure(error):
                    self.errorMessage = error.localizedDescription
                }
                continuation.resume()
            }
        }
    }

    func loadMore() {
        guard hasLoaded, !isLoading, !isLoadingMore, let nextPageURL else { return }
        isLoadingMore = true
        QuestionAnswersRepository.shared.fetch(question: question, nextURL: nextPageURL) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingMore = false
            switch result {
            case let .success(page):
                let existingIDs = Set(self.items.map(\.id))
                self.items.append(contentsOf: page.items.filter {
                    $0.contentID != self.excludingAnswerID && !existingIDs.contains($0.id)
                })
                self.nextPageURL = page.nextURL
            case let .failure(error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func vote(item: FeedItem, completion: @escaping (Result<Void, Error>) -> Void) {
        guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else {
            completion(.failure(ZhihuSessionError.authenticationRequired))
            return
        }
        guard let contentID = item.contentID, contentID > 0 else {
            completion(.failure(ZhihuSessionError.malformedPayload))
            return
        }
        let requested = !item.isVoted
        ZhihuActionRepository.shared.vote(contentID: contentID, kind: item.kind, up: requested) { [weak self] result in
            guard let self = self else { return }
            if case let .success(mutation) = result,
               let index = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[index].isVoted = mutation.isVoted
                if let count = mutation.upvoteCount {
                    self.items[index].upvotes = max(0, count)
                } else {
                    self.items[index].upvotes = max(0, self.items[index].upvotes + (mutation.isVoted ? 1 : -1))
                }
            }
            completion(result.map { _ in () })
        }
    }
}

struct SwiftUIAnswersView: View {
    let question: FeedItem
    let excludingAnswerID: Int64?
    @StateObject private var store: SwiftUIAnswersStore
    @State private var commentsItem: FeedItem?
    @State private var shareItem: FeedItem?
    @State private var actionMessage: String?

    init(question: FeedItem, excludingAnswerID: Int64? = nil) {
        self.question = question
        self.excludingAnswerID = excludingAnswerID
        _store = StateObject(wrappedValue: SwiftUIAnswersStore(question: question, excludingAnswerID: excludingAnswerID))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(question.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                if let errorMessage = store.errorMessage, store.items.isEmpty {
                    SwiftUIErrorCard(message: errorMessage) { store.load() }
                        .padding(.horizontal, 16)
                }
                if store.isLoading && store.items.isEmpty {
                    ProgressView("正在加载回答")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
                ForEach(store.items, id: \.id) { item in
                    SwiftUIFeedCardLink(
                        item: item,
                        onVote: {
                            store.vote(item: item) { result in
                                if case let .failure(error) = result {
                                    actionMessage = error.localizedDescription
                                }
                            }
                        },
                        onComment: { commentsItem = item },
                        onShare: { shareItem = item }
                    )
                    .onAppear {
                        if item.id == store.items.last?.id { store.loadMore() }
                    }
                }
                if store.isLoadingMore {
                    ProgressView("正在加载更多")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                if store.hasLoaded && store.items.isEmpty && store.errorMessage == nil {
                    SwiftUIEmptyState(title: "暂时没有回答", systemImage: "text.bubble")
                }
            }
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)
        }
        .refreshable { await store.refresh() }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("全部回答")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isLoading)
            }
        }
        .onAppear {
            if !store.hasLoaded { store.load() }
        }
        .sheet(isPresented: Binding(
            get: { commentsItem != nil },
            set: { if !$0 { commentsItem = nil } }
        )) {
            if let commentsItem = commentsItem {
                UIKitNavigationScreen { CommentsViewController(item: commentsItem) }
            }
        }
        .sheet(isPresented: Binding(
            get: { shareItem != nil },
            set: { if !$0 { shareItem = nil } }
        )) {
            if let shareItem = shareItem {
                UIKitShareSheet(items: [shareItem.title])
            }
        }
        .alert("知乎", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("好的", role: .cancel) { actionMessage = nil }
        } message: {
            Text(actionMessage ?? "")
        }
    }
}

struct SwiftUIRichContentView: UIViewRepresentable {
    let markup: String
    @Binding var height: CGFloat
    let onOpenURL: (URL) -> Void

    func makeUIView(context: Context) -> RichContentView {
        let view = RichContentView()
        let heightBinding = $height
        view.onOpenURL = onOpenURL
        view.onHeightChange = { value in
            DispatchQueue.main.async { heightBinding.wrappedValue = max(28, value) }
        }
        view.load(markup: markup)
        return view
    }

    func updateUIView(_ uiView: RichContentView, context: Context) {
        let heightBinding = $height
        uiView.onOpenURL = onOpenURL
        uiView.onHeightChange = { value in
            DispatchQueue.main.async { heightBinding.wrappedValue = max(28, value) }
        }
        uiView.load(markup: markup)
    }
}

func makeSwiftUIDetailViewController(item: FeedItem) -> UIViewController {
    UIHostingController(rootView: SwiftUIDetailDestinationView(item: item))
}

struct CachedRemoteImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var loadedURLString: String?

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: didFail ? "photo" : "photo.on.rectangle.angled")
                    .font(.system(size: 28, weight: .medium)).foregroundColor(.secondary.opacity(0.7))
            }
        }
        .clipped()
        .onAppear(perform: load)
        .onChange(of: url?.absoluteString) { _ in
            image = nil
            didFail = false
            load()
        }
    }

    private func load() {
        guard let url else { didFail = true; return }
        let requestedURL = url.absoluteString
        loadedURLString = requestedURL
        ImagePipeline.shared.image(for: url) { image in
            guard loadedURLString == requestedURL else { return }
            self.image = image
            self.didFail = image == nil
        }
    }
}

struct CachedAvatar: View {
    let url: URL?
    let name: String
    let color: UIColor
    let size: CGFloat

    var body: some View {
        CachedRemoteImage(url: url)
            .overlay {
                if url == nil { Text(String(name.prefix(1))).font(.system(size: size * 0.36, weight: .semibold)).foregroundColor(.white) }
            }
            .frame(width: size, height: size)
            .background(Color(uiColor: color))
            .clipShape(Circle())
    }
}

struct SwiftUIProfileView: View {
    @StateObject private var store = SwiftUIProfileStore()
    @State private var showLogin = false
    @State private var showHistory = false
    @State private var showAccounts = false
    @State private var showAppLock = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    profileHeader
                    if store.isLoggedIn {
                        profileTabs
                        if let error = store.errorMessage {
                            SwiftUIErrorCard(message: error) { store.load(tab: store.tab) }
                        }
                        if store.isLoading && store.items.isEmpty { ProgressView("正在读取你的内容").frame(maxWidth: .infinity).padding(30) }
                        ForEach(store.items, id: \.id) { item in
                            SwiftUIFeedCardLink(item: item)
                        }
                        if store.items.isEmpty && !store.isLoading { SwiftUIEmptyState(title: "这里还没有公开内容", systemImage: "doc.text") }
                    } else {
                        SwiftUIEmptyState(title: "登录后同步你的知乎内容", systemImage: "person.crop.circle")
                        Button("登录知乎") { showLogin = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    }
                    management
                }
                .frame(width: min(860, max(0, geometry.size.width - 32)), alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("我的")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(store.isLoggedIn ? "退出" : "登录") { store.isLoggedIn ? store.signOut() : (showLogin = true) }
            }
        }
        .onAppear {
            store.load()
        }
        .sheet(isPresented: $showLogin) { UIKitNavigationScreen { LoginViewController() } }
        .sheet(isPresented: $showHistory) { UIKitNavigationScreen { HistoryViewController() } }
        .sheet(isPresented: $showAccounts) { UIKitNavigationScreen { AccountListViewController() } }
        .sheet(isPresented: $showAppLock) { UIKitNavigationScreen { AppLockSettingsViewController() } }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                CachedAvatar(url: store.profile?.avatarURL ?? store.remoteProfile?.avatarURL, name: store.profile?.name ?? store.remoteProfile?.name ?? "知", color: AppTheme.zhihuBlue, size: 76)
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.profile?.name ?? store.remoteProfile?.name ?? "知乎用户")
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                    Text(store.profile?.headline ?? store.remoteProfile?.headline ?? (store.isLoggedIn ? "记录思考，分享发现" : "登录后同步你的收藏、历史与账号信息"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let profile = store.remoteProfile {
                HStack(spacing: 0) {
                    ProfileStat(value: profile.answerCount, title: "回答")
                    ProfileStat(value: profile.articleCount, title: "文章")
                    ProfileStat(value: profile.followerCount, title: "粉丝")
                    ProfileStat(value: profile.followingCount, title: "关注")
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.16)))
    }

    private var profileTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProfileContentTab.allCases) { tab in
                    Button(tab.title) { store.load(tab: tab) }
                        .font(.subheadline.weight(store.tab == tab ? .semibold : .regular))
                        .foregroundColor(store.tab == tab ? .white : .primary)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(store.tab == tab ? Color(red: 0.08, green: 0.38, blue: 0.86) : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                }
            }
        }
    }

    private var management: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("更多").font(.headline).padding(.horizontal, 4)
            ProfileActionRow(title: "浏览记录", image: "clock.arrow.circlepath") { showHistory = true }
            ProfileActionRow(title: "账号管理", image: "person.2") { showAccounts = true }
            ProfileActionRow(title: "App 锁", image: "lock.shield") { showAppLock = true }
        }
    }
}

struct ProfileStat: View {
    let value: Int
    let title: String
    var body: some View { VStack(spacing: 3) { Text(value.formatted()).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.75); Text(title).font(.caption).foregroundColor(.secondary).lineLimit(1) }.frame(maxWidth: .infinity) }
}

struct ProfileActionRow: View {
    let title: String; let image: String; let action: () -> Void
    var body: some View { Button(action: action) { HStack { Image(systemName: image).foregroundColor(Color(red: 0.08, green: 0.38, blue: 0.86)).frame(width: 24); Text(title).lineLimit(1); Spacer(minLength: 8); Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }.buttonStyle(.plain) }
}

final class SwiftUIProfileStore: ObservableObject {
    @Published var profile: ZhihuProfile?
    @Published var remoteProfile: RemotePersonProfile?
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published var tab: ProfileContentTab = .answers
    @Published private(set) var isLoggedIn = false
    @Published var errorMessage: String?

    func load() {
        let account = ZhihuAccountStore.shared.load()
        isLoggedIn = account?.isLoggedIn == true
        profile = account?.profile
        errorMessage = nil
        guard isLoggedIn else { items = []; return }
        ZhihuAPIClient.shared.fetchProfile { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(profile):
                self.profile = profile
                self.errorMessage = nil
            case let .failure(error):
                self.errorMessage = error.localizedDescription
            }
            self.load(tab: self.tab)
        }
        RemoteProfileRepository.shared.fetchProfile { [weak self] result in
            if case let .success(profile) = result { self?.remoteProfile = profile }
        }
    }

    func load(tab: ProfileContentTab) {
        self.tab = tab
        guard isLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        RemoteProfileRepository.shared.fetchContent(tab: tab) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            switch result {
            case let .success(items): self.items = items
            case let .failure(error): self.errorMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        try? ZhihuAccountStore.shared.clear()
        isLoggedIn = false; profile = nil; remoteProfile = nil; items = []
    }
}

struct SwiftUICollectionView: View {
    @State private var items = Array(SampleData.recommendations.prefix(3))
    var body: some View {
        ScrollView { LazyVStack(spacing: 14) { ForEach(items, id: \.id) { item in SwiftUIFeedCardLink(item: item) } }.padding(16) }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("收藏")
            .onAppear {
                load()
            }
    }
    private func load() { guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else { return }; RemoteLibraryRepository.shared.fetchSavedItems { result in if case let .success(value) = result, !value.isEmpty { items = value } } }
}

struct SwiftUISearchView: View {
    @State private var query = ""
    @State private var results: [FeedItem] = []
    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索问题、话题或用户", text: $query).textFieldStyle(.roundedBorder).padding()
            if results.isEmpty { SwiftUIEmptyState(title: query.isEmpty ? "输入关键词开始探索" : "没有找到相关内容", systemImage: "magnifyingglass").frame(maxHeight: .infinity) }
            else { ScrollView { LazyVStack(spacing: 14) { ForEach(results, id: \.id) { item in SwiftUIFeedCardLink(item: item) }.padding(16) } } }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("搜索")
        .onChange(of: query) { value in search(value) }
    }
    private func search(_ value: String) { let text = value.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { results = []; return }; RemoteFeedRepository.shared.search(query: text) { result in if case let .success(items) = result { results = items } } }
}

struct SwiftUIEmptyState: View {
    let title: String; let systemImage: String
    var body: some View { VStack(spacing: 10) { Image(systemName: systemImage).font(.system(size: 30)).foregroundColor(.secondary); Text(title).font(.subheadline).foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 38) }
}

struct SwiftUIErrorCard: View {
    let message: String; let retry: () -> Void
    var body: some View { HStack(spacing: 12) { Image(systemName: "wifi.exclamationmark").foregroundColor(.orange); Text(message).font(.subheadline).foregroundColor(.secondary).lineLimit(2); Spacer(); Button("重试", action: retry).font(.subheadline.weight(.semibold)) }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
}

struct UIKitNavigationScreen: UIViewControllerRepresentable {
    let make: () -> UIViewController
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = make()
        if let navigation = controller as? UINavigationController { return navigation }
        return UINavigationController(rootViewController: controller)
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

struct UIKitShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
