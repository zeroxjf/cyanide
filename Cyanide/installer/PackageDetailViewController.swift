//
//  PackageDetailViewController.swift
//  Cyanide
//
//  Installer-style detail page for a single package.
//

import UIKit

private let kCallRecordingDisclosureAcceptedDefault = "installer.CallRecordingSoundDisclosureAccepted"

private enum PackageDetailSection: Int {
    case warning      = 0
    case knownIssues  = 1
    case info         = 2
    case action       = 3
    case settings     = 4
    case description  = 5
    static let count  = 6
}

@objc class PackageDetailViewController: UITableViewController {

    private let package: Package
    private var infoRows: [[String]] = []       // [[label, value], ...]
    private var visibleSections: [Int] = []     // ordered PackageDetailSection raw values
    private var settingsSummary: [[String: String]] = []

    @objc(presentCallRecordingDisclosureIfNeededFromViewController:confirmHandler:)
    static func presentCallRecordingDisclosureIfNeeded(from presenter: UIViewController,
                                                       confirmHandler: (() -> Void)?) {
        let d = UserDefaults.standard
        if d.bool(forKey: kCallRecordingDisclosureAcceptedDefault) {
            confirmHandler?()
            return
        }
        let alert = UIAlertController(
            title: "Call Recording Disclosure",
            message: "Silencing call-recording disclosure sounds may violate consent, notice, or privacy laws where you live or where the call participants are located. Only use this where you have permission and understand the rules that apply to you.\n\nCyanide modifies CallServices system files and keeps a backup when possible. You can restore the original sounds from this package.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "I Understand, Silence", style: .destructive) { _ in
            d.set(true, forKey: kCallRecordingDisclosureAcceptedDefault)
            confirmHandler?()
        })
        presenter.present(alert, animated: true)
    }

    @objc init(package: Package) {
        self.package = package
        super.init(style: .insetGrouped)
        infoRows = [
            ["Author",  package.author],
            ["Version", package.version],
        ]
        var sections: [Int] = []
        if (package.unstableWarning ?? "").count > 0 {
            sections.append(PackageDetailSection.warning.rawValue)
        }
        if (package.knownIssues ?? []).count > 0 {
            sections.append(PackageDetailSection.knownIssues.rawValue)
        }
        if package.settingsSection != NSIntegerMax && !package.isInstallDisabled {
            sections.append(PackageDetailSection.action.rawValue)
        }
        settingsSummary = (SettingsViewController.settingsSummary(forSection: package.settingsSection) as? [[String: String]]) ?? []
        if !settingsSummary.isEmpty {
            sections.append(PackageDetailSection.settings.rawValue)
        }
        sections.append(PackageDetailSection.info.rawValue)
        sections.append(PackageDetailSection.description.rawValue)
        visibleSections = sections
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Helpers

    private func sectionAt(_ index: Int) -> PackageDetailSection {
        return PackageDetailSection(rawValue: visibleSections[index]) ?? .description
    }

    private var isOTAPackage: Bool { package.kind == .OTA }

    private var isManualPackage: Bool {
        return package.kind == .OTA
            || package.kind == .NanoRegistry
            || package.kind == .CallRecordingSound
            || package.kind == .HideHomeBar
    }

    private var isDirectToolPackage: Bool { package.kind == .DirectTool }

    private func manualActionTitle(for intent: PackageQueueIntent) -> String {
        if intent != .None {
            if package.kind == .NanoRegistry {
                return intent == .Install ? "Cancel Apply" : "Cancel Remove"
            }
            if package.kind == .CallRecordingSound {
                return intent == .Install ? "Cancel Silence" : "Cancel Restore"
            }
            if package.kind == .HideHomeBar {
                return intent == .Install ? "Cancel Hide" : "Cancel Restore"
            }
            return intent == .Install ? "Cancel Disable" : "Cancel Enable"
        }
        if package.kind == .NanoRegistry       { return "Apply/Remove" }
        if package.kind == .CallRecordingSound  { return "Silence/Restore" }
        if package.kind == .HideHomeBar         { return "Hide/Restore" }
        return "Disable/Enable"
    }

    private var manualStateText: String {
        let intent = PackageQueue.shared().intent(for: package)
        if package.kind == .NanoRegistry {
            if intent == .Install   { return "Apply Pending" }
            if intent == .Uninstall { return "Remove Pending" }
            return "Manual Control"
        }
        if package.kind == .CallRecordingSound {
            if intent == .Install   { return "Silence Pending" }
            if intent == .Uninstall { return "Restore Pending" }
            return "Manual Control"
        }
        if package.kind == .HideHomeBar {
            if intent == .Install   { return "Hide Pending" }
            if intent == .Uninstall { return "Restore Pending" }
            return "Manual Control"
        }
        if intent == .Install   { return "Disable Pending" }
        if intent == .Uninstall { return "Enable Pending" }
        return "Manual Control"
    }

    private var toggleStateText: String {
        let intent = PackageQueue.shared().intent(for: package)
        if intent == .Install   { return "Activation Pending" }
        if intent == .Uninstall { return "Deactivation Pending" }
        if package.isInstalled  { return "Installed" }
        return "Inactive"
    }

    private var toggleStateColor: UIColor {
        let intent = PackageQueue.shared().intent(for: package)
        if intent == .Install   { return view.tintColor }
        if intent == .Uninstall { return .systemRed }
        if package.isInstalled  { return .systemGreen }
        return .secondaryLabel
    }

    private var packageStateText: String {
        if isDirectToolPackage { return "Manual Control" }
        return isManualPackage ? manualStateText : toggleStateText
    }

    private var packageStateColor: UIColor {
        if isDirectToolPackage { return .secondaryLabel }
        return isManualPackage ? manualStateColor : toggleStateColor
    }

    private var manualStateColor: UIColor {
        let intent = PackageQueue.shared().intent(for: package)
        if intent != .None { return view.tintColor }
        return .secondaryLabel
    }

    /// Returns true if a conflict alert was shown (caller should abort).
    private func presentQueueConflictIfNeeded(for intent: PackageQueueIntent) -> Bool {
        var reason: NSString? = nil
        if PackageQueue.shared().canQueue(intent, for: package, reason: &reason) {
            return false
        }
        let msg = (reason as String?) ?? "Hide Home Bar must be the only pending queue item."
        let alert = UIAlertController(title: "Run Hide Home Bar Alone",
                                      message: msg,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        return true
    }

    private var currentInfoRows: [[String]] {
        var rows = infoRows
        rows.append(["State", packageStateText])
        return rows
    }

    private func queueManualIntent(_ intent: PackageQueueIntent) {
        if presentQueueConflictIfNeeded(for: intent) { return }
        if package.kind == .NanoRegistry {
            let op = intent == .Install ? "apply" : "remove"
            "[INSTALLER] Pending watch-pairing \(op)\n".withCString { cyanide_log($0) }
        } else if package.kind == .CallRecordingSound {
            let op = intent == .Install ? "silence" : "restore"
            "[INSTALLER] Pending call-recording sound \(op)\n".withCString { cyanide_log($0) }
        } else if package.kind == .HideHomeBar {
            let op = intent == .Install ? "hide" : "restore"
            "[INSTALLER] Pending home bar \(op)\n".withCString { cyanide_log($0) }
        } else {
            let op = intent == .Install ? "disable" : "enable"
            "[INSTALLER] Pending OTA \(op)\n".withCString { cyanide_log($0) }
        }
        PackageQueue.shared().queueIntent(intent, for: package)
    }

    private func manualActionMenu() -> UIMenu {
        if package.kind == .NanoRegistry {
            let apply = UIAction(title: "Apply Pairing Override",
                                 image: UIImage(systemName: "applewatch.radiowaves.left.and.right")) { [weak self] _ in
                self?.queueManualIntent(.Install)
            }
            var remove = UIAction(title: "Remove Pairing Override",
                                  image: UIImage(systemName: "xmark.circle")) { [weak self] _ in
                self?.queueManualIntent(.Uninstall)
            }
            remove.attributes = .destructive
            return UIMenu(title: "Watch Pairing Override", children: [apply, remove])
        }

        if package.kind == .CallRecordingSound {
            var silence = UIAction(title: "Silence Disclosure Sounds",
                                   image: UIImage(systemName: "speaker.slash.fill")) { [weak self] _ in
                guard let self = self else { return }
                PackageDetailViewController.presentCallRecordingDisclosureIfNeeded(from: self) {
                    self.queueManualIntent(.Install)
                }
            }
            silence.attributes = .destructive
            let restore = UIAction(title: "Restore Original Sounds",
                                   image: UIImage(systemName: "speaker.wave.2.fill")) { [weak self] _ in
                self?.queueManualIntent(.Uninstall)
            }
            return UIMenu(title: "Call Recording Sound", children: [silence, restore])
        }

        if package.kind == .HideHomeBar {
            var hide = UIAction(title: "Hide Home Bar",
                                image: UIImage(systemName: "line.3.horizontal")) { [weak self] _ in
                self?.queueManualIntent(.Install)
            }
            hide.attributes = .destructive
            let restore = UIAction(title: "Restore Home Bar",
                                   image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                self?.queueManualIntent(.Uninstall)
            }
            return UIMenu(title: "Home Bar", children: [hide, restore])
        }

        // OTA
        var disable = UIAction(title: "Disable OTA Updates",
                               image: UIImage(systemName: "icloud.slash")) { [weak self] _ in
            self?.queueManualIntent(.Install)
        }
        disable.attributes = .destructive
        let enable = UIAction(title: "Enable OTA Updates",
                              image: UIImage(systemName: "icloud")) { [weak self] _ in
            self?.queueManualIntent(.Uninstall)
        }
        return UIMenu(title: "OTA Updates", children: [disable, enable])
    }

    private var hasSettingsBundle: Bool { package.settingsSection != NSIntegerMax }

    private var requiresThemeSelection: Bool {
        package.identifier == "com.darksword.themer"
    }

    private var isLiveWPPackage: Bool {
        package.identifier == "com.darksword.livewp"
    }

    private var needsThemeBeforeInstall: Bool {
        requiresThemeSelection && !package.isInstalled && !settings_themer_has_selected_theme()
    }

    private var needsLiveWPVideoBeforeInstall: Bool {
        isLiveWPPackage && !package.isInstalled && !SettingsViewController.liveWPHasSelectedVideo()
    }

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = package.name
        tableView.tableHeaderView = buildHeaderView()
        updateActionButton()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(queueDidChange(_:)),
                                               name: .PackageQueueDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(queueDidChange(_:)),
                                               name: .settingsActionsDidComplete,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settingsSummary = (SettingsViewController.settingsSummary(forSection: package.settingsSection) as? [[String: String]]) ?? []
        tableView.tableHeaderView = buildHeaderView()
        tableView.reloadData()
        updateActionButton()
    }

    @objc private func queueDidChange(_ note: Notification) {
        guard isViewLoaded else { return }
        tableView.tableHeaderView = buildHeaderView()
        tableView.reloadData()
        updateActionButton()
    }

    // MARK: - Header

    private func buildHeaderView() -> UIView {
        let width = view.bounds.size.width
        let intent = PackageQueue.shared().intent(for: package)
        let header = UIView()
        header.backgroundColor = .clear

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.image = UIImage(systemName: package.symbolName)
        iconView.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 48.0, weight: .regular)
        iconView.tintColor = view.tintColor
        header.addSubview(iconView)

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = package.name
        nameLabel.font = .systemFont(ofSize: 22.0, weight: .bold)
        nameLabel.textColor = .label
        nameLabel.textAlignment = .center
        header.addSubview(nameLabel)

        let subLabel = UILabel()
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.text = "\(package.category)  ·  Version \(package.version)"
        subLabel.font = .systemFont(ofSize: 13.0, weight: .regular)
        subLabel.textColor = .secondaryLabel
        subLabel.textAlignment = .center
        header.addSubview(subLabel)

        var badge: UIView? = nil
        if isDirectToolPackage {
            badge = self.badge(text: "MANUAL",
                               background: UIColor.secondaryLabel.withAlphaComponent(0.16),
                               textColor: .secondaryLabel)
        } else if isManualPackage {
            let color = manualStateColor
            badge = self.badge(text: manualStateText.uppercased(),
                               background: color.withAlphaComponent(0.16),
                               textColor: color)
        } else if intent != .None || package.isInstalled {
            let color = packageStateColor
            badge = self.badge(text: packageStateText.uppercased(),
                               background: color.withAlphaComponent(0.16),
                               textColor: color)
        } else if package.creatorOnly {
            badge = self.badge(text: "IN DEVELOPMENT",
                               background: UIColor.systemPurple.withAlphaComponent(0.16),
                               textColor: .systemPurple)
        } else if package.experimental {
            badge = self.badge(text: "EXPERIMENTAL",
                               background: UIColor.systemRed.withAlphaComponent(0.16),
                               textColor: .systemRed)
        } else if package.isInstallDisabled {
            badge = self.badge(text: "DISABLED",
                               background: UIColor.systemRed.withAlphaComponent(0.16),
                               textColor: .systemRed)
        } else if package.isNew {
            badge = self.badge(text: "NEW",
                               background: UIColor(red: 0.95, green: 0.55, blue: 0.05, alpha: 0.18),
                               textColor: .systemOrange)
        }
        if let b = badge {
            b.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(b)
        }

        var cs: [NSLayoutConstraint] = [
            iconView.topAnchor.constraint(equalTo: header.topAnchor, constant: 16.0),
            iconView.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 60.0),
            iconView.heightAnchor.constraint(equalToConstant: 54.0),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12.0),
            nameLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16.0),
            nameLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16.0),

            subLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3.0),
            subLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16.0),
            subLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16.0),
        ]
        if let b = badge {
            cs += [
                b.topAnchor.constraint(equalTo: subLabel.bottomAnchor, constant: 12.0),
                b.centerXAnchor.constraint(equalTo: header.centerXAnchor),
                b.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -14.0),
            ]
        } else {
            cs.append(subLabel.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12.0))
        }
        NSLayoutConstraint.activate(cs)

        let fit = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        header.frame = CGRect(x: 0, y: 0, width: width, height: fit.height)
        return header
    }

    private func badge(text: String, background: UIColor, textColor: UIColor) -> UIView {
        let container = UIView()
        container.backgroundColor = background
        container.layer.cornerRadius = 12.0
        container.layer.cornerCurve = .continuous
        container.layer.masksToBounds = true

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 11.0, weight: .heavy)
        label.textColor = textColor
        label.textAlignment = .center
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4.0),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4.0),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10.0),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10.0),
        ])
        return container
    }

    // MARK: - Action button

    private func updateActionButton() {
        let intent = PackageQueue.shared().intent(for: package)
        let installed = package.isInstalled
        let manual = isManualPackage
        let directTool = isDirectToolPackage

        var title: String
        var style: UIBarButtonItem.Style = .plain
        var tint: UIColor? = nil
        if directTool {
            title = "Open Controls"
            tint = view.tintColor
            style = .done
        } else if manual {
            title = manualActionTitle(for: intent)
            tint = (intent != .None) ? .secondaryLabel : view.tintColor
            if intent == .None { style = .done }
        } else if intent != .None {
            title = "Cancel"
            tint = .secondaryLabel
        } else if installed && isLiveWPPackage && hasSettingsBundle {
            title = "Change Video"
            tint = view.tintColor
            style = .done
        } else if installed {
            title = "Deactivate"
            tint = .systemRed
        } else if package.creatorOnly && !cyanide_is_creator() {
            title = "In Development"
            tint = .secondaryLabel
        } else if package.isInstallDisabled {
            title = "Disabled"
            tint = .secondaryLabel
        } else if needsThemeBeforeInstall {
            title = "Select Theme"
            style = .done
        } else if needsLiveWPVideoBeforeInstall {
            title = "Select Video"
            style = .done
        } else {
            title = "Activate"
            style = .done
        }

        let useMenu = manual && intent == .None
        let item = UIBarButtonItem(title: title,
                                   style: style,
                                   target: useMenu ? nil : self,
                                   action: useMenu ? nil : #selector(didTapAction))
        if useMenu {
            item.menu = manualActionMenu()
        }
        if let t = tint { item.tintColor = t }
        item.isEnabled = !package.isInstallDisabled || installed || intent != .None
        navigationItem.rightBarButtonItem = item
    }

    @objc private func didTapAction() {
        let intent = PackageQueue.shared().intent(for: package)
        if intent != .None {
            "[INSTALLER] Removed \(package.name) from queue\n".withCString { cyanide_log($0) }
            PackageQueue.shared().remove(package)
            return
        }
        if package.creatorOnly && !cyanide_is_creator() { return }
        if package.isInstallDisabled && !package.isInstalled {
            "[INSTALLER] \(package.name) is disabled for now: \(package.installDisabledReason)\n"
                .withCString { cyanide_log($0) }
            return
        }
        if needsThemeBeforeInstall {
            promptSelectThemeBeforeInstall()
            return
        }
        if needsLiveWPVideoBeforeInstall {
            navigateToSettingsSection()
            return
        }
        if isDirectToolPackage {
            navigateToSettingsSection()
            return
        }
        if package.isInstalled && isLiveWPPackage && hasSettingsBundle {
            navigateToSettingsSection()
            return
        }
        if false && !package.isInstalled && hasSettingsBundle {
            promptConfigureBeforeInstall()
            return
        }
        if isManualPackage { return }
        if package.isInstalled {
            if presentQueueConflictIfNeeded(for: .Uninstall) { return }
            "[INSTALLER] Pending deactivation: \(package.name)\n".withCString { cyanide_log($0) }
        } else {
            if presentQueueConflictIfNeeded(for: .Install) { return }
            "[INSTALLER] Pending activation: \(package.name)\n".withCString { cyanide_log($0) }
        }
        PackageQueue.shared().toggle(for: package)
    }

    private func promptSelectThemeBeforeInstall() {
        let alert = UIAlertController(title: "Select a Theme",
                                      message: "Icon themes need a selected theme before they can be activated. Choose iOS 6 Theme or import a custom theme first.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Open Theme Settings", style: .default) { [weak self] _ in
            self?.navigateToSettingsSection()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func promptConfigureBeforeInstall() {
        let msg = "\(package.name) has configurable options. Set them up first so the tweak applies with your preferences on the first activation."
        let alert = UIAlertController(title: "Customize Before Activating?",
                                      message: msg,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Configure First", style: .default) { [weak self] _ in
            self?.navigateToSettingsSection()
        })
        alert.addAction(UIAlertAction(title: "Activate Anyway", style: .default) { [weak self] _ in
            guard let self = self else { return }
            if self.presentQueueConflictIfNeeded(for: .Install) { return }
            "[INSTALLER] Pending activation: \(self.package.name)\n".withCString { cyanide_log($0) }
            PackageQueue.shared().toggle(for: self.package)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return visibleSections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionAt(section) {
        case .warning:     return 1
        case .knownIssues: return 1
        case .info:        return currentInfoRows.count
        case .action:      return 1
        case .settings:    return settingsSummary.count
        case .description: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sectionAt(section) {
        case .warning:     return nil
        case .knownIssues: return "Known Issues"
        case .info:        return nil
        case .action:      return "Configure"
        case .settings:    return "Current Settings"
        case .description: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if sectionAt(section) == .action {
            return "Settings can be changed before or after activation."
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sectionAt(indexPath.section) {
        case .warning: {
            var cell = tableView.dequeueReusableCell(withIdentifier: "WarningCell")
            if cell == nil {
                cell = UITableViewCell(style: .default, reuseIdentifier: "WarningCell")
                cell?.selectionStyle = .none
            }
            let c = cell!
            for v in c.contentView.subviews { v.removeFromSuperview() }
            c.textLabel?.text = nil
            c.imageView?.image = nil
            c.backgroundColor = UIColor.systemRed.withAlphaComponent(0.14)

            let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.tintColor = .systemRed
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .semibold)
            icon.setContentHuggingPriority(.required, for: .horizontal)
            icon.setContentCompressionResistancePriority(.required, for: .horizontal)
            c.contentView.addSubview(icon)

            let lbl = UILabel()
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.text = package.unstableWarning
            lbl.textColor = .systemRed
            lbl.font = .systemFont(ofSize: 14.0, weight: .semibold)
            lbl.numberOfLines = 0
            c.contentView.addSubview(lbl)

            let m = c.contentView.layoutMarginsGuide
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: m.leadingAnchor),
                icon.topAnchor.constraint(equalTo: m.topAnchor, constant: 2.0),
                icon.widthAnchor.constraint(equalToConstant: 22.0),

                lbl.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10.0),
                lbl.trailingAnchor.constraint(equalTo: m.trailingAnchor),
                lbl.topAnchor.constraint(equalTo: m.topAnchor),
                lbl.bottomAnchor.constraint(equalTo: m.bottomAnchor),
            ])
            return c
        }()

        case .knownIssues: {
            var cell = tableView.dequeueReusableCell(withIdentifier: "KnownIssuesCell")
            if cell == nil {
                cell = UITableViewCell(style: .default, reuseIdentifier: "KnownIssuesCell")
                cell?.selectionStyle = .none
            }
            let c = cell!
            for v in c.contentView.subviews { v.removeFromSuperview() }
            c.textLabel?.text = nil
            c.imageView?.image = nil
            c.backgroundColor = .clear

            let issues = package.knownIssues as! [String]
            let accent = UIColor.systemOrange

            let card = UIView()
            card.translatesAutoresizingMaskIntoConstraints = false
            card.backgroundColor = accent.withAlphaComponent(0.06)
            card.layer.borderColor = accent.withAlphaComponent(0.35).cgColor
            card.layer.borderWidth = 1.0
            card.layer.cornerRadius = 10.0
            card.layer.cornerCurve = .continuous
            card.layer.masksToBounds = true

            let ps = NSMutableParagraphStyle()
            ps.headIndent = 12.0
            ps.firstLineHeadIndent = 0.0
            ps.paragraphSpacing = 6.0
            ps.lineSpacing = 1.0

            let bulletAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13.0),
                .foregroundColor: accent,
                .paragraphStyle: ps,
            ]
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13.0),
                .foregroundColor: UIColor.label,
                .paragraphStyle: ps,
            ]

            let body = NSMutableAttributedString()
            for (i, issue) in issues.enumerated() {
                if i > 0 { body.append(NSAttributedString(string: "\n")) }
                body.append(NSAttributedString(string: "•  ", attributes: bulletAttrs))
                body.append(NSAttributedString(string: issue, attributes: textAttrs))
            }

            let bodyLabel = UILabel()
            bodyLabel.translatesAutoresizingMaskIntoConstraints = false
            bodyLabel.attributedText = body
            bodyLabel.numberOfLines = 0

            card.addSubview(bodyLabel)
            c.contentView.addSubview(card)

            let m = c.contentView.layoutMarginsGuide
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: m.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: m.trailingAnchor),
                card.topAnchor.constraint(equalTo: m.topAnchor),
                card.bottomAnchor.constraint(equalTo: m.bottomAnchor),

                bodyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                bodyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                bodyLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
                bodyLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            ])
            return c
        }()

        case .info: {
            var cell = tableView.dequeueReusableCell(withIdentifier: "InfoCell")
            if cell == nil {
                cell = UITableViewCell(style: .value1, reuseIdentifier: "InfoCell")
                cell?.selectionStyle = .none
            }
            let c = cell!
            let rows = currentInfoRows
            let row = indexPath.row < rows.count ? rows[indexPath.row] : []
            let label = row.count > 0 ? row[0] : ""
            let value = row.count > 1 ? row[1] : ""
            c.textLabel?.text = label
            c.detailTextLabel?.text = value
            c.detailTextLabel?.textColor = (label == "State") ? packageStateColor : .secondaryLabel
            c.detailTextLabel?.lineBreakMode = .byTruncatingMiddle
            return c
        }()

        case .description: {
            let kDescID = "DescCell"
            var cell = tableView.dequeueReusableCell(withIdentifier: kDescID)
            if cell == nil {
                cell = UITableViewCell(style: .default, reuseIdentifier: kDescID)
                cell?.selectionStyle = .none
            }
            let c = cell!
            for v in c.contentView.subviews { v.removeFromSuperview() }
            c.textLabel?.text = nil

            let descLabel = UILabel()
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            descLabel.numberOfLines = 0
            descLabel.font = .systemFont(ofSize: 14.0, weight: .regular)
            descLabel.textColor = .secondaryLabel

            let ps = NSMutableParagraphStyle()
            ps.lineSpacing = 3.0
            ps.paragraphSpacing = 10.0
            descLabel.attributedText = NSAttributedString(
                string: package.longDescription ?? "",
                attributes: [
                    .font: descLabel.font!,
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: ps,
                ])

            c.contentView.addSubview(descLabel)
            let m = c.contentView.layoutMarginsGuide
            NSLayoutConstraint.activate([
                descLabel.topAnchor.constraint(equalTo: m.topAnchor, constant: 2.0),
                descLabel.bottomAnchor.constraint(equalTo: m.bottomAnchor, constant: -2.0),
                descLabel.leadingAnchor.constraint(equalTo: m.leadingAnchor),
                descLabel.trailingAnchor.constraint(equalTo: m.trailingAnchor),
            ])
            return c
        }()

        case .settings: {
            var cell = tableView.dequeueReusableCell(withIdentifier: "SettingsSummaryCell")
            if cell == nil {
                cell = UITableViewCell(style: .value1, reuseIdentifier: "SettingsSummaryCell")
                cell?.selectionStyle = .none
                cell?.detailTextLabel?.textColor = .secondaryLabel
            }
            let c = cell!
            let row = settingsSummary[indexPath.row]
            c.textLabel?.text = row["title"]
            c.detailTextLabel?.text = row["value"]
            return c
        }()

        case .action: {
            var cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell")
            if cell == nil {
                cell = UITableViewCell(style: .subtitle, reuseIdentifier: "ActionCell")
            }
            let c = cell!
            c.textLabel?.text = isDirectToolPackage
                ? "Open \(package.name)"
                : "Customize \(package.name)"
            c.textLabel?.textColor = view.tintColor
            c.textLabel?.font = .systemFont(ofSize: 17.0, weight: .semibold)
            c.detailTextLabel?.text = isDirectToolPackage
                ? "Choose a target and run actions directly"
                : "Adjust options in the Settings tab"
            c.detailTextLabel?.textColor = .secondaryLabel
            c.imageView?.image = UIImage(systemName: "slider.horizontal.3")
            c.imageView?.tintColor = view.tintColor
            c.accessoryType = .disclosureIndicator
            return c
        }()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard sectionAt(indexPath.section) == .action else { return }
        guard hasSettingsBundle else { return }
        navigateToSettingsSection()
    }

    private func navigateToSettingsSection() {
        guard let tab = tabBarController else { return }
        var settingsIndex: Int? = nil
        var settingsNav: UINavigationController? = nil
        for (i, vc) in (tab.viewControllers ?? []).enumerated() {
            if vc.tabBarItem.title == "Settings" {
                settingsIndex = i
                settingsNav = vc as? UINavigationController
                break
            }
        }
        guard let idx = settingsIndex, let nav = settingsNav else { return }
        nav.popToRootViewController(animated: false)
        let bundle = SettingsViewController(underlyingSection: package.settingsSection,
                                            bundleTitle: package.name)
        bundle?.installerReturnPackageName = package.name
        if let bundle = bundle {
            nav.pushViewController(bundle, animated: false)
        }
        tab.selectedIndex = idx
    }
}
