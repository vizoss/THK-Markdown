import UIKit

// No UIApplicationSceneManifest is declared in Info.plist, so iOS falls back to this
// classic window-based lifecycle instead of requiring a SceneDelegate — the simplest
// setup for a small example app with no storyboard.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: MainViewController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
