//
//  InstallProgressViewController.swift
//  Cyanide
//
//  Sileo-style install progress sheet: live log + spinner during apply, then
//  "Done" once settings_run_actions completes.
//

import UIKit
import Darwin

@objc class InstallProgressViewController: UIViewController {

    @objc var promptsForHideHomeBarRespring: Bool = false

    private var bannerLabel: UILabel!
    private var logView: LogTextView!
    private var spinner: UIActivityIndicatorView!
    private var statusLabel: UILabel!
    private var hideOrDoneButton: UIBarButtonItem!
    private var completed: Bool = false
    private var didPromptForHideHomeBarRespring: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        let bg = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1.0)
        view.backgroundColor = bg
        title = "Activity"
        isModalInPresentation = false

        bannerLabel = UILabel()
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false
        bannerLabel.numberOfLines = 0
        bannerLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        bannerLabel.textColor = UIColor(white: 0.86, alpha: 1.0)
        bannerLabel.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1.0)
        bannerLabel.textAlignment = .left
        bannerLabel.attributedText = buildBannerText()
        bannerLabel.layer.cornerRadius = 10
        bannerLabel.clipsToBounds = true
        view.addSubview(bannerLabel)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(white: 1.0, alpha: 0.07)
        view.addSubview(separator)

        logView = LogTextView(frame: .zero)
        logView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logView)

        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let footer = UIVisualEffectView(effect: blur)
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)

        let footerDivider = UIView()
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        footerDivider.backgroundColor = UIColor(white: 1.0, alpha: 0.07)
        footer.contentView.addSubview(footerDivider)

        spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = UIColor(white: 0.75, alpha: 1.0)
        spinner.startAnimating()
        footer.contentView.addSubview(spinner)

        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Running — stay here until complete."
        statusLabel.font = .systemFont(ofSize: 13.5, weight: .regular)
        statusLabel.textColor = UIColor(white: 0.55, alpha: 1.0)
        statusLabel.numberOfLines = 1
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.8
        footer.contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            bannerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            bannerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bannerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            separator.topAnchor.constraint(equalTo: bannerLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            logView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            logView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            logView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 64.0),

            footerDivider.topAnchor.constraint(equalTo: footer.topAnchor),
            footerDivider.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            footerDivider.heightAnchor.constraint(equalToConstant: 0.5),

            spinner.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20.0),
            spinner.centerYAnchor.constraint(equalTo: footer.safeAreaLayoutGuide.topAnchor, constant: 22.0),
            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 12.0),
            statusLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20.0),
            statusLabel.centerYAnchor.constraint(equalTo: spinner.centerYAnchor),
        ])

        hideOrDoneButton = UIBarButtonItem(title: "Hide",
                                           style: .plain,
                                           target: self,
                                           action: #selector(didTapDone))
        navigationItem.rightBarButtonItem = hideOrDoneButton

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveCompleteNotification(_:)),
                                               name: .settingsActionsDidComplete,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func didReceiveCompleteNotification(_ note: Notification) {
        if completed { return }
        completed = true
        spinner.stopAnimating()
        spinner.isHidden = true
        let successValue = note.userInfo?[kSettingsActionsDidCompleteSuccessKey] as? NSNumber
        let success = successValue?.boolValue ?? true
        let message = note.userInfo?[kSettingsActionsDidCompleteMessageKey] as? String
        if let msg = message, !msg.isEmpty {
            statusLabel.text = msg
        } else {
            statusLabel.text = success ? "All tweaks applied in-session." : "Failed — check the log above."
        }
        statusLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        statusLabel.textColor = success
            ? UIColor(red: 0.38, green: 0.90, blue: 0.55, alpha: 1.0)
            : UIColor(red: 1.0, green: 0.38, blue: 0.32, alpha: 1.0)
        title = success ? "Complete" : "Failed"
        hideOrDoneButton.title = "Done"
        if success && promptsForHideHomeBarRespring && settings_hide_home_bar_respring_pending() {
            scheduleHideHomeBarRespringPrompt()
        }
    }

    private func scheduleHideHomeBarRespringPrompt() {
        if didPromptForHideHomeBarRespring { return }
        didPromptForHideHomeBarRespring = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, self.view.window != nil else { return }
            settings_present_hide_home_bar_respring_prompt(self)
        }
    }

    private func buildBannerText() -> NSAttributedString {
        let b = Bundle.main
        let info = b.infoDictionary
        let shortVer = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build    = info?["CFBundleVersion"] as? String ?? "?"

        var u = utsname()
        uname(&u)
        let machine: String = withUnsafePointer(to: &u.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        let machineStr = machine.isEmpty ? "device" : machine
        let ios = UIDevice.current.systemVersion

        let banner = """
             ╭───────────╮
             │ ▄▄▄▄▄▄▄▄▄ │
             ├───────────┤
             │ ░░░░░░░░░ │   C Y A N I D E
             │ ░░░ C ░░░ │   \(shortVer) (\(build))
             │ ░░░░░░░░░ │   \(machineStr) • iOS \(ios)
             │ ░░░░░░░░░ │
             ╰───────────╯
        """

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2.0

        return NSAttributedString(string: banner, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: UIColor(white: 0.86, alpha: 1.0),
            .paragraphStyle: para,
        ])
    }

    @objc private func didTapDone() {
        let presenter = presentingViewController
        let nav: UINavigationController?
        if let n = presenter as? UINavigationController {
            nav = n
        } else {
            nav = presenter?.navigationController
        }
        dismiss(animated: true) {
            guard let nav = nav else { return }
            var stack = nav.viewControllers
            var removed = 0
            for i in stride(from: stack.count - 1, through: 0, by: -1) {
                if stack[i] is QueueReviewViewController {
                    stack.remove(at: i)
                    removed += 1
                }
            }
            if removed > 0 {
                nav.setViewControllers(stack, animated: true)
            }
        }
    }
}
