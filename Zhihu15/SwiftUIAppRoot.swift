import SwiftUI
import UIKit

struct SwiftUIAppRootView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView { SwiftUIHomeView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("首页", systemImage: "house") }
                .tag(0)

            NavigationView { SwiftUICollectionView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("收藏", systemImage: "bookmark") }
                .tag(1)

            NavigationView { SwiftUIProfileView() }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(2)
        }
        .accentColor(Color(red: 0.08, green: 0.38, blue: 0.86))
        .onReceive(NotificationCenter.default.publisher(for: .zhihuHandoffOpenItem)) { _ in
            selectedTab = 0
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
    @State private var detailRoute: SwiftUIDetailRoute?
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
                    SwiftUIFeedCard(
                        item: item,
                        onOpen: { detailRoute = SwiftUIDetailRoute(item: item) },
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
        .onAppear { if !store.hasLoaded { store.load() } }
        .onReceive(autoRefreshTimer) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zhihuHandoffOpenItem)) { notification in
            if let item = notification.object as? FeedItem {
                detailRoute = SwiftUIDetailRoute(item: item)
            }
        }
        .background(SwiftUIPushDetailLink(route: $detailRoute))
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
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(red: 0.08, green: 0.38, blue: 0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("探索你的知乎").font(.headline)
                    Text("回答、文章、想法与热榜，一处浏览").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            Button { showSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    Text("搜索问题、话题或用户").foregroundColor(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).frame(height: 44)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Picker("内容频道", selection: Binding(get: { store.channel.rawValue }, set: { store.load(channel: HomeChannel(rawValue: $0) ?? .recommendation) })) {
                Text("推荐").tag(0); Text("关注").tag(1); Text("热榜").tag(2); Text("日报").tag(3)
            }
            .pickerStyle(.segmented)
        }
    }
}

struct SwiftUIFeedCard: View {
    let item: FeedItem
    var onOpen: (() -> Void)? = nil
    var onVote: (() -> Void)? = nil

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
                Label(item.comments > 0 ? "\(item.comments)" : "评论", systemImage: "bubble.left")
                Spacer()
                Text(item.topic).font(.caption).foregroundColor(Color(red: 0.08, green: 0.38, blue: 0.86))
            }
            .font(.caption.weight(.medium)).foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(uiColor: .separator).opacity(0.16)))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onOpen?() }
    }
}

struct SwiftUIDetailRoute: Identifiable { let id = UUID(); let item: FeedItem }

final class SwiftUIDetailActionBridge: ObservableObject {
    var openComments: (() -> Void)?
    var openCanonicalURL: (() -> Void)?
    var openVideo: (() -> Void)?
}

struct SwiftUIPushDetailLink: View {
    @Binding var route: SwiftUIDetailRoute?

    var body: some View {
        NavigationLink(
            destination: destination,
            isActive: Binding(
                get: { route != nil },
                set: { isActive in
                    if !isActive { route = nil }
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
            SwiftUIDetailContainer(item: route.item)
        } else {
            EmptyView()
        }
    }
}

private struct SwiftUIDetailContainer: View {
    let item: FeedItem
    @StateObject private var actionBridge = SwiftUIDetailActionBridge()

    var body: some View {
        UIKitDetailScreen(item: item, actionBridge: actionBridge)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if item.kind == .video {
                        Button { actionBridge.openVideo?() } label: {
                            Image(systemName: "play.circle")
                        }
                        .accessibilityLabel("播放")
                    }
                    Button { actionBridge.openComments?() } label: {
                        Image(systemName: "bubble.left")
                    }
                    .accessibilityLabel("评论")
                    Button { actionBridge.openCanonicalURL?() } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("在知乎打开")
                }
            }
    }
}

struct UIKitDetailScreen: UIViewControllerRepresentable {
    let item: FeedItem
    let actionBridge: SwiftUIDetailActionBridge?

    init(item: FeedItem, actionBridge: SwiftUIDetailActionBridge? = nil) {
        self.item = item
        self.actionBridge = actionBridge
    }

    func makeUIViewController(context: Context) -> DetailViewController {
        let viewController = DetailViewController(item: item, managesNavigationBar: actionBridge != nil)
        actionBridge?.openComments = { [weak viewController] in viewController?.openCommentsFromNavigationHost() }
        actionBridge?.openCanonicalURL = { [weak viewController] in viewController?.openCanonicalURLFromNavigationHost() }
        actionBridge?.openVideo = { [weak viewController] in viewController?.openVideoFromNavigationHost() }
        return viewController
    }

    func updateUIViewController(_ viewController: DetailViewController, context: Context) {
        viewController.navigationItem.prompt = nil
        viewController.navigationItem.largeTitleDisplayMode = .never
    }
}

struct CachedRemoteImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var loadedURLString: String?

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image).resizable().scaledToFill()
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
    @State private var detailRoute: SwiftUIDetailRoute?
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
                            SwiftUIFeedCard(item: item, onOpen: { detailRoute = SwiftUIDetailRoute(item: item) })
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
        .onAppear { store.load() }
        .sheet(isPresented: $showLogin) { UIKitNavigationScreen { LoginViewController() } }
        .sheet(isPresented: $showHistory) { UIKitNavigationScreen { HistoryViewController() } }
        .sheet(isPresented: $showAccounts) { UIKitNavigationScreen { AccountListViewController() } }
        .sheet(isPresented: $showAppLock) { UIKitNavigationScreen { AppLockSettingsViewController() } }
        .background(SwiftUIPushDetailLink(route: $detailRoute))
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                CachedAvatar(url: store.profile?.avatarURL, name: store.profile?.name ?? "知", color: AppTheme.zhihuBlue, size: 76)
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.profile?.name ?? "知乎用户")
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                    Text(store.profile?.headline ?? (store.isLoggedIn ? "记录思考，分享发现" : "登录后同步你的收藏、历史与账号信息"))
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
            if case let .failure(error) = result { self?.errorMessage = error.localizedDescription }
            self?.load(tab: self?.tab ?? .answers)
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
    @State private var detailRoute: SwiftUIDetailRoute?
    var body: some View {
        ScrollView { LazyVStack(spacing: 14) { ForEach(items, id: \.id) { item in SwiftUIFeedCard(item: item, onOpen: { detailRoute = SwiftUIDetailRoute(item: item) }) } }.padding(16) }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("收藏")
            .onAppear { load() }
            .background(SwiftUIPushDetailLink(route: $detailRoute))
    }
    private func load() { guard ZhihuAccountStore.shared.load()?.isLoggedIn == true else { return }; RemoteLibraryRepository.shared.fetchSavedItems { result in if case let .success(value) = result, !value.isEmpty { items = value } } }
}

struct SwiftUISearchView: View {
    @State private var query = ""
    @State private var results: [FeedItem] = []
    @State private var detailRoute: SwiftUIDetailRoute?
    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索问题、话题或用户", text: $query).textFieldStyle(.roundedBorder).padding()
            if results.isEmpty { SwiftUIEmptyState(title: query.isEmpty ? "输入关键词开始探索" : "没有找到相关内容", systemImage: "magnifyingglass").frame(maxHeight: .infinity) }
            else { ScrollView { LazyVStack(spacing: 14) { ForEach(results, id: \.id) { item in SwiftUIFeedCard(item: item, onOpen: { detailRoute = SwiftUIDetailRoute(item: item) }) }.padding(16) } } }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("搜索")
        .onChange(of: query) { value in search(value) }
        .background(SwiftUIPushDetailLink(route: $detailRoute))
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
