//
//  QueueReviewViewController.swift
//  Cyanide
//
//  Sileo "DownloadsTableViewController" analog: shows the queued
//  install/uninstall operations and offers CONFIRM / CLEAR actions.
//

import UIKit

private enum QueueReviewSection: Int {
    case install   = 0
    case uninstall = 1
    case reApply   = 2
    static let count = 3
}

@objc class QueueReviewViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private var tableView: UITableView!
    private var confirmButton: UIButton!
    private var clearButton: UIButton!
    private var emptyLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Queue"
        view.backgroundColor = .systemGroupedBackground

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        let footer = buildFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)

        emptyLabel = UILabel()
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No pending changes\nQueue packages from the Installer tab"
        emptyLabel.font = .systemFont(ofSize: 16.0, weight: .medium)
        emptyLabel.textColor = .tertiaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24.0),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24.0),
        ])

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(queueChanged(_:)),
                                               name: .PackageQueueDidChange,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshUI()
    }

    private func buildFooter() -> UIView {
        let container = UIView()
        container.backgroundColor = .systemGroupedBackground

        var confirmCfg = UIButton.Configuration.filled()
        confirmCfg.title = "Confirm"
        confirmCfg.cornerStyle = .large
        confirmCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attrs = incoming
            attrs.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
            return attrs
        }
        let confirmButton = UIButton(configuration: confirmCfg,
                                     primaryAction: UIAction { [weak self] _ in self?.didTapConfirm() })
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(confirmButton)
        self.confirmButton = confirmButton

        var clearCfg = UIButton.Configuration.plain()
        clearCfg.title = "Clear Queue"
        clearCfg.baseForegroundColor = .systemRed
        clearCfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attrs = incoming
            attrs.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
            return attrs
        }
        let clearButton = UIButton(configuration: clearCfg,
                                    primaryAction: UIAction { [weak self] _ in self?.didTapClear() })
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(clearButton)
        self.clearButton = clearButton

        NSLayoutConstraint.activate([
            confirmButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8.0),
            confirmButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16.0),
            confirmButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.0),
            confirmButton.heightAnchor.constraint(equalToConstant: 50.0),

            clearButton.topAnchor.constraint(equalTo: confirmButton.bottomAnchor, constant: 2.0),
            clearButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            clearButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8.0),
        ])
        return container
    }

    private func refreshUI() {
        tableView.reloadData()
        updateHomeBarWarningHeader()
        let count = PackageQueue.shared().pendingCount
        emptyLabel.isHidden = count > 0
        tableView.isHidden = count == 0
        confirmButton.isEnabled = count > 0
        clearButton.isEnabled = count > 0

        let confirmTitle: String
        if count == 1 {
            confirmTitle = "Confirm 1 Change"
        } else if count > 1 {
            confirmTitle = "Confirm \(count) Changes"
        } else {
            confirmTitle = "Confirm"
        }
        var cfg = confirmButton.configuration
        cfg?.title = confirmTitle
        confirmButton.configuration = cfg
    }

    private func homeBarWarningHeaderView() -> UIView {
        var width = tableView.bounds.size.width
        if width <= 0.0 { width = view.bounds.size.width }
        if width <= 0.0 { width = UIScreen.main.bounds.size.width }

        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        container.backgroundColor = .systemGroupedBackground

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.14)
        card.layer.cornerRadius = 16.0
        card.layer.borderWidth = 1.0
        card.layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.28).cgColor
        container.addSubview(card)

        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .systemOrange
        icon.contentMode = .scaleAspectFit
        card.addSubview(icon)

        let titleLbl = UILabel()
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        titleLbl.text = "Hide Home Bar must run alone"
        titleLbl.font = .systemFont(ofSize: 16.0, weight: .bold)
        titleLbl.textColor = .label
        card.addSubview(titleLbl)

        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.text = "It edits the system home-indicator asset and then needs a respring. Confirm only Hide Home Bar, respring, then queue your other tweaks."
        body.font = .systemFont(ofSize: 13.0, weight: .regular)
        body.textColor = .secondaryLabel
        body.numberOfLines = 0
        card.addSubview(body)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor, constant: 12.0),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16.0),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.0),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8.0),

            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 14.0),
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
            icon.widthAnchor.constraint(equalToConstant: 24.0),
            icon.heightAnchor.constraint(equalToConstant: 24.0),

            titleLbl.topAnchor.constraint(equalTo: card.topAnchor, constant: 12.0),
            titleLbl.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10.0),
            titleLbl.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),

            body.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 4.0),
            body.leadingAnchor.constraint(equalTo: titleLbl.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: titleLbl.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12.0),
        ])

        let size = container.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                     withHorizontalFittingPriority: .required,
                                                     verticalFittingPriority: .fittingSizeLevel)
        container.frame = CGRect(x: 0, y: 0, width: width, height: ceil(size.height))
        return container
    }

    private func updateHomeBarWarningHeader() {
        if !queueIncludesHideHomeBar() {
            tableView.tableHeaderView = nil
            return
        }
        tableView.tableHeaderView = homeBarWarningHeaderView()
    }

    @objc private func queueChanged(_ note: Notification) {
        refreshUI()
    }

    // MARK: - Table helpers

    private func reApplyPackages() -> [Package] {
        if queueIncludesHideHomeBar() { return [] }
        let q = PackageQueue.shared()
        return PackageCatalog.allPackages().compactMap { p -> Package? in
            guard p.isInstalled else { return nil }
            guard q.intent(for: p) != .Uninstall else { return nil }
            return p
        }
    }

    private func packages(for section: Int) -> [Package] {
        let q = PackageQueue.shared()
        switch QueueReviewSection(rawValue: section) {
        case .install:   return q.queuedInstalls as! [Package]
        case .uninstall: return q.queuedUninstalls as! [Package]
        case .reApply:   return reApplyPackages()
        default:         return []
        }
    }

    private func queueIncludesHideHomeBar() -> Bool {
        let q = PackageQueue.shared()
        for pkg in q.queuedInstalls as! [Package] {
            if pkg.kind == .HideHomeBar { return true }
        }
        for pkg in q.queuedUninstalls as! [Package] {
            if pkg.kind == .HideHomeBar { return true }
        }
        return false
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return QueueReviewSection.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return packages(for: section).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let list = packages(for: section)
        guard !list.isEmpty else { return nil }
        let commonKind = list.first!.kind
        let allSameKind = list.allSatisfy { $0.kind == commonKind }

        let label: String
        switch QueueReviewSection(rawValue: section) {
        case .install:
            if allSameKind && commonKind == .OTA           { label = "Disable" }
            else if allSameKind && commonKind == .NanoRegistry  { label = "Apply" }
            else if allSameKind && commonKind == .CallRecordingSound { label = "Silence" }
            else if allSameKind && commonKind == .HideHomeBar   { label = "Hide" }
            else                                               { label = "Activate" }
        case .uninstall:
            if allSameKind && commonKind == .OTA           { label = "Enable" }
            else if allSameKind && commonKind == .NanoRegistry  { label = "Remove" }
            else if allSameKind && commonKind == .CallRecordingSound { label = "Restore" }
            else if allSameKind && commonKind == .HideHomeBar   { label = "Restore" }
            else                                               { label = "Deactivate" }
        case .reApply: label = "Already Active"
        default: return nil
        }
        return "\(label)  ·  \(list.count)"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch QueueReviewSection(rawValue: section) {
        case .install:
            if !queueIncludesHideHomeBar() { return nil }
            return "Hide Home Bar must run by itself because it edits the system home-indicator asset and then needs a respring. Run it alone first, then apply other tweaks after the respring."
        case .reApply:
            if reApplyPackages().isEmpty { return nil }
            return "These are already installed, not new pending changes. Confirming re-runs the chain so RemoteCall-backed tweaks come back after a force-quit. To stop one from running, deactivate it from the Installer tab, or use Reset All Packages in Settings → Quick Actions."
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "QueueRow")
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "QueueRow")
        }
        let c = cell!
        let pkgList = packages(for: indexPath.section)
        guard indexPath.row < pkgList.count else {
            c.textLabel?.text = "No longer pending"
            c.textLabel?.font = .systemFont(ofSize: 17.0, weight: .regular)
            c.detailTextLabel?.text = "This queue row was already applied or cleared."
            c.detailTextLabel?.textColor = .secondaryLabel
            c.detailTextLabel?.font = .systemFont(ofSize: 12.0)
            c.imageView?.image = UIImage(systemName: "checkmark.circle")
            c.imageView?.tintColor = .tertiaryLabel
            c.selectionStyle = .none
            c.accessoryView = nil
            c.accessoryType = .none
            return c
        }

        let pkg = pkgList[indexPath.row]
        c.textLabel?.text = pkg.name
        c.textLabel?.font = .systemFont(ofSize: 17.0, weight: .semibold)

        let s = QueueReviewSection(rawValue: indexPath.section)
        switch s {
        case .install:
            switch pkg.kind {
            case .OTA:
                c.detailTextLabel?.text = "Pending OTA disable"
                c.detailTextLabel?.textColor = .systemOrange
            case .NanoRegistry:
                c.detailTextLabel?.text = "Pending override apply"
                c.detailTextLabel?.textColor = view.tintColor
            case .CallRecordingSound:
                c.detailTextLabel?.text = "Pending sound silence"
                c.detailTextLabel?.textColor = .systemOrange
            case .HideHomeBar:
                c.detailTextLabel?.text = "Runs alone; respring required"
                c.detailTextLabel?.textColor = .systemOrange
            default:
                c.detailTextLabel?.text = "Activation pending"
                c.detailTextLabel?.textColor = .systemGreen
            }
        case .uninstall:
            switch pkg.kind {
            case .OTA:
                c.detailTextLabel?.text = "Pending OTA enable"
                c.detailTextLabel?.textColor = .systemGreen
            case .NanoRegistry:
                c.detailTextLabel?.text = "Pending override remove"
                c.detailTextLabel?.textColor = .systemRed
            case .CallRecordingSound:
                c.detailTextLabel?.text = "Pending sound restore"
                c.detailTextLabel?.textColor = .systemGreen
            case .HideHomeBar:
                c.detailTextLabel?.text = "Pending respring restore"
                c.detailTextLabel?.textColor = .systemGreen
            default:
                c.detailTextLabel?.text = "Deactivation pending"
                c.detailTextLabel?.textColor = .systemRed
            }
        case .reApply:
            c.detailTextLabel?.text = "Active; will refresh"
            c.detailTextLabel?.textColor = .secondaryLabel
        default:
            c.detailTextLabel?.text = nil
        }
        c.detailTextLabel?.font = .systemFont(ofSize: 12.0)
        c.imageView?.image = UIImage(systemName: pkg.symbolName)
        c.imageView?.tintColor = (s == .reApply) ? .tertiaryLabel : view.tintColor
        c.selectionStyle = .none
        c.accessoryView = nil
        c.accessoryType = .none
        return c
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let s = QueueReviewSection(rawValue: indexPath.section)
        guard s == .install || s == .uninstall else { return nil }
        let pkgList = packages(for: indexPath.section)
        guard indexPath.row < pkgList.count else { return nil }
        let pkg = pkgList[indexPath.row]
        let remove = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            _ = self
            PackageQueue.shared().remove(pkg)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }

    // MARK: - Actions

    private func didTapConfirm() {
        let q = PackageQueue.shared()
        guard q.pendingCount > 0 else { return }
        let count = q.pendingCount

        var includesHideHomeBar = false
        for pkg in q.queuedInstalls as! [Package] {
            if pkg.kind == .HideHomeBar { includesHideHomeBar = true; break }
        }
        if !includesHideHomeBar {
            for pkg in q.queuedUninstalls as! [Package] {
                if pkg.kind == .HideHomeBar { includesHideHomeBar = true; break }
            }
        }

        if includesHideHomeBar && count > 1 {
            let ac = UIAlertController(title: "Run Hide Home Bar Alone",
                                       message: "Hide Home Bar edits the system home-indicator asset and needs a respring after it applies. Remove the other pending changes, run Hide Home Bar by itself, then apply other tweaks after the respring.",
                                       preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
            return
        }

        let vc = InstallProgressViewController()
        vc.promptsForHideHomeBarRespring = includesHideHomeBar
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .automatic
        present(nav, animated: true) {
            "[INSTALLER] ── Applying \(count) pending change(s) ──\n".withCString { cyanide_log($0) }
            PackageQueue.shared().commit()
        }
    }

    private func didTapClear() {
        guard PackageQueue.shared().pendingCount > 0 else { return }
        let ac = UIAlertController(title: "Clear Queue?",
                                   message: "Discard all pending activation / deactivation changes.",
                                   preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        ac.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            PackageQueue.shared().clear()
        })
        present(ac, animated: true)
    }
}
