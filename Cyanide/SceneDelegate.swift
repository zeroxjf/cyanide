import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var didSelectInitialTab = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let tab = window?.rootViewController as? UITabBarController,
              tab.viewControllers?.count ?? 0 > 1 else { return }

        // iOS 26+: collapse floating tab bar into a pill on scroll-down.
        tab_bar_apply_scroll_minimize(tab)
    }

    private func selectInitialTabIfNeeded() {
        guard !didSelectInitialTab else { return }
        guard let tab = window?.rootViewController as? UITabBarController,
              let vcs = tab.viewControllers, !vcs.isEmpty else { return }
        didSelectInitialTab = true
        tab.selectedIndex = 0
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    private func runUpdateCheck() {
        guard let tab = window?.rootViewController as? UITabBarController else { return }
        UpdateChecker.shared().checkForUpdatesIfNeeded(from: tab)
    }

    private func showSignalGroupNoticeIfNeeded() {
        let ud = UserDefaults.standard
        let noticeKey = "cyanide.community.signalGroupNoticeShown"
        guard !ud.bool(forKey: noticeKey) else { return }
        guard let root = window?.rootViewController else { return }

        let msg = "Created a Signal group as the main place for Cyanide feedback and support.\n\nUse it to report bugs, request features, share test results, ask setup questions, and get notes about new builds."
        let alert = UIAlertController(
            title: "Join the Cyanide Signal Group",
            message: msg,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Join Signal", style: .default) { _ in
            ud.set(true, forKey: noticeKey)
            ud.synchronize()
            if let url = URL(string: "https://signal.group/#CjQKIP0pxjc9V52ddCNk--04DosuoQl-vVOsznJfQ4GwlrlxEhCveFhBS8YdNcILpUFt7IqC") {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel) { _ in
            ud.set(true, forKey: noticeKey)
            ud.synchronize()
        })
        root.present(alert, animated: true)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        selectInitialTabIfNeeded()
        settings_application_did_become_active()
        showSignalGroupNoticeIfNeeded()
        runUpdateCheck()
    }

    func sceneWillResignActive(_ scene: UIScene) {}

    func sceneWillEnterForeground(_ scene: UIScene) {
        settings_application_will_enter_foreground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        settings_application_did_enter_background()
    }
}
