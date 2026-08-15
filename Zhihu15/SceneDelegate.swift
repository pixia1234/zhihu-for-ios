import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        AppTheme.configureNavigationBar(UINavigationBar.appearance())
        AppTheme.configureTabBar(UITabBar.appearance())
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: SwiftUIAppRootView())
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        AppLockCoordinator.shared.lock()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let window = window else { return }
        DispatchQueue.main.async { AppLockCoordinator.shared.presentIfNeeded(in: window) }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .all
    }
}
