import UIKit

enum AppTheme {
    static let zhihuBlue = UIColor(red: 0.08, green: 0.38, blue: 0.86, alpha: 1)
    static let text = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let card = UIColor.secondarySystemGroupedBackground
    static let border = UIColor.separator.withAlphaComponent(0.35)

    static func configureNavigationBar(_ navigationBar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = .systemBackground
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: text]
        appearance.largeTitleTextAttributes = [.foregroundColor: text]
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = zhihuBlue
        navigationBar.prefersLargeTitles = true
    }

    static func configureTabBar(_ tabBar: UITabBar) {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.20)
        appearance.shadowColor = border
        tabBar.isTranslucent = true
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = zhihuBlue
        tabBar.unselectedItemTintColor = secondaryText
    }

    static func configureToolbar(_ toolbar: UIToolbar) {
        let appearance = UIToolbarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.22)
        appearance.shadowColor = border
        toolbar.isTranslucent = true
        toolbar.standardAppearance = appearance
        toolbar.compactAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        toolbar.tintColor = zhihuBlue
    }

    /// SwiftUI's TabView owns the concrete UITabBar instance. Appearance
    /// proxies can be applied before that instance is created on iOS 15,
    /// so apply the same material to the live hierarchy as well.
    static func configureTabBars(in root: UIViewController?) {
        guard let root else { return }
        configureTabBars(in: root.view)
        for child in root.children {
            configureTabBars(in: child)
        }
        if let presented = root.presentedViewController {
            configureTabBars(in: presented)
        }
    }

    static func configureToolbars(in root: UIViewController?) {
        guard let root else { return }
        configureToolbars(in: root.view)
        for child in root.children {
            configureToolbars(in: child)
        }
        if let presented = root.presentedViewController {
            configureToolbars(in: presented)
        }
    }

    private static func configureTabBars(in view: UIView?) {
        guard let view else { return }
        if let tabBar = view as? UITabBar {
            configureTabBar(tabBar)
        }
        for subview in view.subviews {
            configureTabBars(in: subview)
        }
    }

    private static func configureToolbars(in view: UIView?) {
        guard let view else { return }
        if let toolbar = view as? UIToolbar {
            configureToolbar(toolbar)
        }
        for subview in view.subviews {
            configureToolbars(in: subview)
        }
    }

    static func setTabBarHidden(_ hidden: Bool) {
        // SwiftUI invokes this from view lifecycle callbacks, but keeping the
        // operation main-thread-only also makes Handoff and UIKit entry points
        // use exactly the same transition behavior.
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                AppTheme.setTabBarHidden(hidden)
            }
            return
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                guard let rootViewController = window.rootViewController else { continue }

                // SwiftUI's TabView owns a live UITabBar, but it is not
                // necessarily hosted by a UITabBarController. Only touch the
                // concrete bars in the root hierarchy; a presented UIKit
                // screen must not become a second tab-bar owner.
                var tabBars: [UITabBar] = []
                collectTabBars(in: rootViewController.view, into: &tabBars)
                // On some iOS 15 builds SwiftUI keeps the TabView bar behind
                // an internal tab-bar controller whose view is not exposed
                // during the first hierarchy walk. Resolve that same live
                // bar as a fallback, without introducing another hide path.
                if let tabBarController = findTabBarController(in: rootViewController),
                   !tabBars.contains(where: { $0 === tabBarController.tabBar }) {
                    tabBars.append(tabBarController.tabBar)
                }
                tabBars.forEach { $0.isHidden = hidden }

                // SwiftUI's TabView has no UITabBarController, so flipping
                // isHidden alone leaves the tab-bar height in the content
                // safe area; a pushed page's bottom toolbar then keeps an
                // extra bottom inset. Re-run the root layout after the
                // push/pop transition has started so the toolbar lays out
                // against the real bottom edge, without suppressing the
                // transition animation the way a synchronous layout pass
                // inside onAppear does.
                let root = rootViewController
                DispatchQueue.main.async {
                    root.view.setNeedsLayout()
                    window.setNeedsLayout()
                    window.layoutIfNeeded()
                    root.view.layoutIfNeeded()
                }
            }
        }
    }

    private static func collectTabBars(in view: UIView?, into tabBars: inout [UITabBar]) {
        guard let view else { return }
        if let tabBar = view as? UITabBar, !tabBars.contains(where: { $0 === tabBar }) {
            tabBars.append(tabBar)
        }
        for subview in view.subviews {
            collectTabBars(in: subview, into: &tabBars)
        }
    }

    private static func findTabBarController(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabBarController = controller as? UITabBarController { return tabBarController }
        for child in controller.children.reversed() {
            if let result = findTabBarController(in: child) { return result }
        }
        return nil
    }
}

final class AvatarView: UIView {
    private let initialsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18
        clipsToBounds = true
        initialsLabel.textAlignment = .center
        initialsLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        initialsLabel.textColor = .white
        addSubview(initialsLabel)
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            initialsLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            initialsLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            initialsLabel.topAnchor.constraint(equalTo: topAnchor),
            initialsLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    func configure(name: String, color: UIColor) {
        initialsLabel.text = String(name.prefix(1))
        initialsLabel.isHidden = false
        backgroundColor = color
        layer.contents = nil
        accessibilityLabel = "用户头像，\(name)"
    }

    func setImage(_ image: UIImage?) {
        layer.contents = image?.cgImage
        layer.contentsGravity = .resizeAspectFill
        initialsLabel.isHidden = image != nil
    }
}

final class PillLabel: UILabel {
    init(text: String) {
        super.init(frame: .zero)
        self.text = text
        textColor = AppTheme.zhihuBlue
        font = .systemFont(ofSize: 12, weight: .medium)
        backgroundColor = AppTheme.zhihuBlue.withAlphaComponent(0.1)
        textAlignment = .center
        layer.cornerRadius = 5
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 12, height: max(size.height + 5, 24))
    }
}
