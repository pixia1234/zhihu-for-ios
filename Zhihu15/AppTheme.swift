import UIKit

enum AppTheme {
    static let zhihuBlue = UIColor(red: 0.08, green: 0.38, blue: 0.86, alpha: 1)
    static let text = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let card = UIColor.secondarySystemGroupedBackground
    static let border = UIColor.separator.withAlphaComponent(0.35)

    /// Gives vote and unvote actions a small, consistent tactile response.
    /// UIKit feedback generators must be driven on the main thread.
    static func performVoteHaptic() {
        let trigger = {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        }
        if Thread.isMainThread {
            trigger()
        } else {
            DispatchQueue.main.async(execute: trigger)
        }
    }

    static func configureNavigationBar(_ navigationBar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.22)
        appearance.shadowColor = border
        appearance.titleTextAttributes = [.foregroundColor: text]
        appearance.largeTitleTextAttributes = [.foregroundColor: text]
        navigationBar.isTranslucent = true
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
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.22)
        appearance.shadowColor = border
        toolbar.isTranslucent = true
        toolbar.standardAppearance = appearance
        toolbar.compactAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        toolbar.tintColor = zhihuBlue
    }

    static func configureNavigationBars(in root: UIViewController?) {
        guard let root else { return }
        configureNavigationBars(in: root.view)
        for child in root.children {
            configureNavigationBars(in: child)
        }
        if let presented = root.presentedViewController {
            configureNavigationBars(in: presented)
        }
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

    /// SwiftUI creates the toolbar for a pushed detail page after the root
    /// scene has appeared on iOS 15. Re-apply the material to those live UIKit
    /// bars once the destination has entered the hierarchy.
    static func refreshLiveAppearance() {
        let apply = {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                for window in scene.windows {
                    guard let root = window.rootViewController else { continue }
                    configureNavigationBars(in: root)
                    configureTabBars(in: root)
                    configureToolbars(in: root)
                }
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
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

    private static func configureNavigationBars(in view: UIView?) {
        guard let view else { return }
        if let navigationBar = view as? UINavigationBar {
            configureNavigationBar(navigationBar)
        }
        for subview in view.subviews {
            configureNavigationBars(in: subview)
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
