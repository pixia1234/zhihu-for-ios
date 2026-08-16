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
        AppTheme.configureToolbar(UIToolbar.appearance())
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: SwiftUIAppRootView())
        self.window = window
        window.makeKeyAndVisible()
        applyTabBarAppearance()
        if let activity = connectionOptions.userActivities.first {
            DispatchQueue.main.async {
                HandoffCoordinator.shared.handle(activity)
            }
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        AppLockCoordinator.shared.lock()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let window = window else { return }
        applyTabBarAppearance()
        DispatchQueue.main.async {
            AppLockCoordinator.shared.presentIfNeeded(in: window)
        }
        // The root SwiftUI controller may finish attaching its view just
        // after sceneDidBecomeActive. Retry once after the presentation
        // context is ready; AppLockCoordinator's state guards prevent a loop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AppTheme.configureNavigationBars(in: window.rootViewController)
            AppTheme.configureTabBars(in: window.rootViewController)
            AppTheme.configureToolbars(in: window.rootViewController)
            AppLockCoordinator.shared.presentIfNeeded(in: window)
        }
    }

    private func applyTabBarAppearance() {
        guard let window else { return }
        AppTheme.configureNavigationBars(in: window.rootViewController)
        AppTheme.configureTabBars(in: window.rootViewController)
        AppTheme.configureToolbars(in: window.rootViewController)
        // SwiftUI may finish installing its TabView after the first layout.
        DispatchQueue.main.async {
            AppTheme.configureNavigationBars(in: window.rootViewController)
            AppTheme.configureTabBars(in: window.rootViewController)
            AppTheme.configureToolbars(in: window.rootViewController)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            AppTheme.configureNavigationBars(in: window.rootViewController)
            AppTheme.configureTabBars(in: window.rootViewController)
            AppTheme.configureToolbars(in: window.rootViewController)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        HandoffCoordinator.shared.handle(userActivity)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .all
    }
}
