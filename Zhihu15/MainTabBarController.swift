import UIKit

final class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        AppTheme.configureTabBar(tabBar)
        viewControllers = [
            navigationController(root: HomeViewController(), title: "首页", image: "house", selectedImage: "house.fill"),
            navigationController(root: CollectionsViewController(), title: "收藏", image: "bookmark", selectedImage: "bookmark.fill"),
            navigationController(root: ProfileViewController(), title: "账号", image: "person.crop.circle", selectedImage: "person.crop.circle.fill"),
            navigationController(root: SearchViewController(), title: "搜索", image: "magnifyingglass", selectedImage: "magnifyingglass")
        ]
        selectedIndex = 0
    }

    private func navigationController(root: UIViewController, title: String, image: String, selectedImage: String) -> UINavigationController {
        root.title = title
        let navigationController = UINavigationController(rootViewController: root)
        navigationController.navigationBar.prefersLargeTitles = true
        AppTheme.configureNavigationBar(navigationController.navigationBar)
        navigationController.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), selectedImage: UIImage(systemName: selectedImage))
        return navigationController
    }
}
