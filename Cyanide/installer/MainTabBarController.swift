import UIKit

private let kPopupHeight:  CGFloat = 56.0
private let kPopupGap:     CGFloat = 8.0
private let kPopupPadding: CGFloat = 2.0

@objc(MainTabBarController) class MainTabBarController: UITabBarController {

    private var popupBar: QueuePopupBar!
    private var popupBarConstraints: [NSLayoutConstraint] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        popupBar = QueuePopupBar(frame: .zero)
        popupBar.translatesAutoresizingMaskIntoConstraints = false
        popupBar.onTap = { [weak self] in self?.showQueueReview() }
        view.addSubview(popupBar)

        installPopupBarConstraintsIfReady()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queueDidChange(_:)),
            name: .PackageQueueDidChange,
            object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installPopupBarConstraintsIfReady()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func sharesHierarchy(_ view: UIView, with otherView: UIView) -> Bool {
        var ancestor: UIView? = view
        while let a = ancestor {
            if otherView.isDescendant(of: a) { return true }
            ancestor = a.superview
        }
        return false
    }

    private func installPopupBarConstraintsIfReady() {
        guard popupBarConstraints.isEmpty else { return }

        var bottomAnchor: NSLayoutYAxisAnchor = view.safeAreaLayoutGuide.bottomAnchor
        let bottomConstant: CGFloat = -kPopupGap
        if sharesHierarchy(popupBar, with: tabBar) {
            bottomAnchor = tabBar.topAnchor
        }

        popupBarConstraints = [
            popupBar.leadingAnchor.constraint(equalTo: view.leadingAnchor,   constant: 12.0),
            popupBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12.0),
            popupBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: bottomConstant),
            popupBar.heightAnchor.constraint(equalToConstant: kPopupHeight),
        ]
        NSLayoutConstraint.activate(popupBarConstraints)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        popupBar.refreshFromQueue(animated: false)
        refreshChildInsets(animated: false)
    }

    override func setViewControllers(_ viewControllers: [UIViewController]?, animated: Bool) {
        super.setViewControllers(viewControllers, animated: animated)
        refreshChildInsets(animated: false)
    }

    // MARK: - Popup inset propagation

    @objc private func queueDidChange(_ note: Notification) {
        refreshChildInsets(animated: true)
    }

    private func refreshChildInsets(animated: Bool) {
        let visible = PackageQueue.shared().pendingCount > 0
        var insets = UIEdgeInsets.zero
        if visible {
            insets.bottom = kPopupHeight + kPopupGap + kPopupPadding
        }
        let apply: () -> Void = { [weak self] in
            self?.viewControllers?.forEach { $0.additionalSafeAreaInsets = insets }
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: apply)
        } else {
            apply()
        }
    }

    private func showQueueReview() {
        guard let selected = selectedViewController else { return }
        let nav: UINavigationController?
        if let n = selected as? UINavigationController {
            nav = n
        } else {
            nav = selected.navigationController
        }
        guard let nav else { return }
        guard !(nav.topViewController is QueueReviewViewController) else { return }
        nav.pushViewController(QueueReviewViewController(), animated: true)
    }
}
