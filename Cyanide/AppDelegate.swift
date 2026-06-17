import UIKit
import Darwin

@objc(AppDelegate) @main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logBootIdentity()
        settings_register_defaults()
        log_set_verbose(true)
        ds_keepalive_apply_enabled(UserDefaults.standard.bool(forKey: kSettingsKeepAlive))
        installTerminationHandlers()
        installBarAppearances()
        return true
    }

    private func logBootIdentity() {
        let info = Bundle.main.infoDictionary
        let shortVer = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build    = info?["CFBundleVersion"] as? String ?? "?"

        var u = utsname()
        uname(&u)
        let machine: String = withUnsafeBytes(of: u.machine) { raw in
            let ptr = raw.bindMemory(to: CChar.self).baseAddress!
            return String(cString: ptr)
        }
        let ios = UIDevice.current.systemVersion

        let banner =
            "\n" +
            "     ╭───────────╮\n" +
            "     │ ▄▄▄▄▄▄▄▄▄ │\n" +
            "     ├───────────┤\n" +
            "     │ ░░░░░░░░░ │   C Y A N I D E\n" +
            "     │ ░░░ C ░░░ │   \(shortVer) (\(build))\n" +
            "     │ ░░░░░░░░░ │   \(machine) • iOS \(ios)\n" +
            "     │ ░░░░░░░░░ │\n" +
            "     ╰───────────╯\n" +
            "\n"
        banner.withCString { cyanide_log($0) }
    }

    private static var sigtermSource: DispatchSourceSignal?
    private static let sigtermOnce = DispatchQueue(label: "cyanide.sigterm.once")
    private static var sigtermInstalled = false

    private func installTerminationHandlers() {
        Self.sigtermOnce.sync {
            guard !Self.sigtermInstalled else { return }
            Self.sigtermInstalled = true

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appWillTerminate(_:)),
                name: UIApplication.willTerminateNotification,
                object: nil)

            signal(SIGTERM, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            src.setEventHandler {
                "[CLEANUP] SIGTERM received; starting best-effort termination cleanup.\n".withCString {
                    cyanide_log($0)
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    settings_best_effort_termination_cleanup("SIGTERM")
                    _Exit(0)
                }
            }
            src.resume()
            Self.sigtermSource = src
        }
    }

    @objc private func appWillTerminate(_ note: Notification) {
        settings_best_effort_termination_cleanup("UIApplicationWillTerminateNotification")
    }

    private func installBarAppearances() {
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance        = nav
        UINavigationBar.appearance().scrollEdgeAppearance      = nav
        UINavigationBar.appearance().compactAppearance         = nav
        UINavigationBar.appearance().compactScrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance   = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    // MARK: - UISceneSession lifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication,
                     didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    func applicationWillTerminate(_ application: UIApplication) {
        settings_best_effort_termination_cleanup("applicationWillTerminate")
    }
}
