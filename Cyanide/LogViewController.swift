import UIKit
import Darwin

@objc(LogViewController) class LogViewController: UIViewController {

    private var bannerLabel: UILabel!
    private var logView: LogTextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Log"
        let bg = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1.0)
        view.backgroundColor = bg

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

        NSLayoutConstraint.activate([
            bannerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            bannerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bannerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            separator.topAnchor.constraint(equalTo: bannerLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            logView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            logView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            logView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            logView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func buildBannerText() -> NSAttributedString {
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

        let banner = """
             ╭───────────╮
             │ ▄▄▄▄▄▄▄▄▄ │
             ├───────────┤
             │ ░░░░░░░░░ │   C Y A N I D E
             │ ░░░ C ░░░ │   \(shortVer) (\(build))
             │ ░░░░░░░░░ │   \(machine) • iOS \(ios)
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
}
