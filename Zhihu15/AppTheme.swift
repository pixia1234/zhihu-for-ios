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
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.82)
        appearance.shadowColor = border
        tabBar.isTranslucent = true
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.tintColor = zhihuBlue
        tabBar.unselectedItemTintColor = secondaryText
    }

    static func setTabBarHidden(_ hidden: Bool) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                if let tabBarController = findTabBarController(in: window.rootViewController) {
                    tabBarController.tabBar.isHidden = hidden
                }
            }
        }
    }

    private static func findTabBarController(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabBarController = controller as? UITabBarController { return tabBarController }
        if let presented = controller.presentedViewController,
           let result = findTabBarController(in: presented) { return result }
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
