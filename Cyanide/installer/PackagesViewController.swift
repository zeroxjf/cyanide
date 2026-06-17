//
//  PackagesViewController.swift
//  Cyanide
//
//  Installer-style packages tab: grouped list of tweaks by category.
//

import UIKit

private let kPackageCellID          = "PackageCell"
private let kGroupByCategoryDefault = "installer.groupByCategory"
private let kTipsExpandedDefault    = "installer.tipsExpanded"
private let kSignalGroupURL         = "https://signal.group/#CjQKIP0pxjc9V52ddCNk--04DosuoQl-vVOsznJfQ4GwlrlxEhCveFhBS8YdNcILpUFt7IqC"
private let kGitHubIssuesURL        = "https://github.com/zeroxjf/cyanide/issues"

@objc(PackagesViewController) class PackagesViewController: UITableViewController, UISearchResultsUpdating {

    private var allPackagesSorted: [Package] = []
    private var flatPackages: [Package] = []          // shown when !groupByCategory
    private var visibleCategories: [String] = []      // shown when groupByCategory
    private var packagesByCategory: [String: [Package]] = [:]
    private var searchText: String = ""
    private var groupByCategory: Bool = false
    private var searchCtl: UISearchController!

    // MARK: - Helpers

    private func packageNeedsThemeBeforeInstall(_ pkg: Package) -> Bool {
        return pkg.identifier == "com.darksword.themer" &&
               !pkg.isInstalled &&
               !settings_themer_has_selected_theme()
    }

    private func packageNeedsLiveWPVideoBeforeInstall(_ pkg: Package) -> Bool {
        return pkg.identifier == "com.darksword.livewp" &&
               !pkg.isInstalled &&
               !SettingsViewController.liveWPHasSelectedVideo()
    }

    private func presentQueueConflictIfNeededForPackage(_ pkg: Package, intent: PackageQueueIntent) -> Bool {
        var reason: NSString? = nil
        if PackageQueue.sharedQueue().canQueueIntent(intent, forPackage: pkg, reason: &reason) {
            return false
        }
        let alert = UIAlertController(
            title: "Run Hide Home Bar Alone",
            message: (reason as String?) ?? "Hide Home Bar must be the only pending queue item.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
        return true
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Installer"
        navigationItem.title = "Installer"

        let ud = UserDefaults.standard
        if ud.object(forKey: kGroupByCategoryDefault) == nil {
            ud.set(true, forKey: kGroupByCategoryDefault)
        }
        groupByCategory = ud.bool(forKey: kGroupByCategoryDefault)
        searchText = ""

        allPackagesSorted = PackageCatalog.allPackages().sorted {
            $0.name.caseInsensitiveCompare($1.name) == .orderedAscending
        }

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68.0
        tableView.sectionFooterHeight = 4.0
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0.0
        }

        searchCtl = UISearchController(searchResultsController: nil)
        searchCtl.searchResultsUpdater = self
        searchCtl.obscuresBackgroundDuringPresentation = false
        searchCtl.searchBar.placeholder = "Search tweaks"
        navigationItem.searchController = searchCtl
        navigationItem.hidesSearchBarWhenScrolling = false

        installSortBarButton()
        installTipsHeader()
        rebuildFilteredData()

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
        refreshCatalog()
        tableView.reloadData()
    }

    private func refreshCatalog() {
        allPackagesSorted = PackageCatalog.allPackages().sorted {
            $0.name.caseInsensitiveCompare($1.name) == .orderedAscending
        }
        rebuildFilteredData()
    }

    @objc private func queueDidChange(_ note: Notification) {
        guard isViewLoaded else { return }
        refreshCatalog()
        tableView.reloadData()
    }

    // MARK: - Sort menu

    private func installSortBarButton() {
        let flat = UIAction(title: "Alphabetical",
                            image: UIImage(systemName: "list.bullet")) { [weak self] _ in
            self?.applyGroupByCategory(false)
        }
        flat.state = groupByCategory ? .off : .on

        let byCat = UIAction(title: "By Category",
                             image: UIImage(systemName: "folder")) { [weak self] _ in
            self?.applyGroupByCategory(true)
        }
        byCat.state = groupByCategory ? .on : .off

        let menu = UIMenu(title: "Sort", children: [flat, byCat])
        let btn = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
                                  menu: menu)
        navigationItem.rightBarButtonItem = btn
    }

    private func applyGroupByCategory(_ group: Bool) {
        guard groupByCategory != group else { return }
        groupByCategory = group
        UserDefaults.standard.set(group, forKey: kGroupByCategoryDefault)
        installSortBarButton()
        rebuildFilteredData()
        tableView.reloadData()
    }

    // MARK: - Tips header

    private func tipsEntries() -> [[String: Any]] {
        return [
            ["icon":  "wand.and.stars",
             "color": UIColor.systemPurple,
             "title": "What's new",
             "body":  "• App Switcher Grid adds a grid-style app switcher option\n• LiveWP now supports video picking from Files and Photos\n• Location Simulator is available as a public Beta tool\n• Call Recording Sound is available as a public Beta package"],
            ["icon":  "exclamationmark.triangle.fill",
             "color": UIColor.systemOrange,
             "title": "Don't force-quit Cyanide",
             "body":  "From the App Switcher kills live tweaks instantly — StatBar, Axon Lite, and anything else running per session stops the moment the app dies."],
            ["icon":  "hand.tap.fill",
             "color": UIColor.systemTeal,
             "title": "New Beta tools",
             "body":  "Try exact-coordinate location simulation, App Switcher Grid, LiveWP video wallpapers, and SnowBoard-style local icon themes from the Installer."],
        ]
    }

    private func openURLString(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func buildSupportButton(title: String,
                                    icon: String,
                                    background: UIColor,
                                    url urlString: String,
                                    width: CGFloat,
                                    height: CGFloat) -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.image = UIImage(systemName: icon)
        cfg.imagePadding = 8.0
        cfg.imagePlacement = .leading
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = background
        cfg.baseForegroundColor = .white
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        let button = UIButton(configuration: cfg,
                              primaryAction: UIAction { [weak self] _ in
            self?.openURLString(urlString)
        })
        button.frame = CGRect(x: 0, y: 0, width: width, height: height)
        button.layer.cornerCurve = .continuous
        return button
    }

    private func buildTipRow(icon iconName: String,
                             color: UIColor,
                             title: String,
                             body: String,
                             width: CGFloat) -> UIView {
        let iconSize: CGFloat  = 22.0
        let iconGap: CGFloat   = 12.0
        let textX: CGFloat     = iconSize + iconGap
        let textWidth: CGFloat = width - textX

        let row = UIView()

        let symCfg = UIImage.SymbolConfiguration(pointSize: 16.0, weight: .semibold)
        let iconView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: symCfg)?
            .withTintColor(color, renderingMode: .alwaysOriginal))
        iconView.contentMode = .center
        iconView.frame = CGRect(x: 0, y: 1, width: iconSize, height: iconSize)
        row.addSubview(iconView)

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 1.5

        let as_ = NSMutableAttributedString()
        as_.append(NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.label,
            .paragraphStyle: para,
        ]))
        as_.append(NSAttributedString(string: "\n", attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
        ]))
        as_.append(NSAttributedString(string: body, attributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: para,
        ]))

        let label = UILabel()
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = textWidth
        label.attributedText = as_
        let fit = label.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        label.frame = CGRect(x: textX, y: 0, width: textWidth, height: fit.height)
        row.addSubview(label)

        row.frame = CGRect(x: 0, y: 0, width: width, height: max(fit.height, iconSize))
        return row
    }

    private func installTipsHeader() {
        var width = tableView.bounds.size.width
        if width <= 0 { width = UIScreen.main.bounds.size.width }

        let horizontalMargin: CGFloat  = 16.0
        let topPadding: CGFloat        = 14.0
        let bottomPadding: CGFloat     = 0.0
        let cardInset: CGFloat         = 14.0
        let contentWidth: CGFloat      = width - horizontalMargin * 2 - cardInset * 2
        let rowGap: CGFloat            = 14.0
        let headingGap: CGFloat        = 10.0
        let supportGap: CGFloat        = 10.0
        let supportButtonGap: CGFloat  = 8.0
        let supportButtonHeight: CGFloat = 46.0
        let chevronSize: CGFloat       = 14.0

        let expanded = UserDefaults.standard.bool(forKey: kTipsExpandedDefault)

        var placed: [UIView] = []
        var y: CGFloat = cardInset

        // Heading
        let heading = UILabel()
        heading.numberOfLines = 1
        let headAS = NSMutableAttributedString()
        let sparkle = NSTextAttachment()
        let headCfg = UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold)
        sparkle.image = UIImage(systemName: "sparkles", withConfiguration: headCfg)?
            .withTintColor(.systemPurple, renderingMode: .alwaysOriginal)
        headAS.append(NSAttributedString(attachment: sparkle))
        headAS.append(NSAttributedString(string: "  What's New & Tips", attributes: [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: UIColor.label,
        ]))
        heading.attributedText = headAS
        let headingWidth = contentWidth - chevronSize - 8.0
        let headFit = heading.sizeThatFits(CGSize(width: headingWidth, height: .greatestFiniteMagnitude))
        heading.frame = CGRect(x: cardInset, y: y, width: headingWidth, height: headFit.height)
        placed.append(heading)

        // Chevron
        let chevCfg = UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold)
        let chevronImg = UIImage(systemName: expanded ? "chevron.up" : "chevron.down",
                                 withConfiguration: chevCfg)?
            .withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal)
        let chevron = UIImageView(image: chevronImg)
        chevron.contentMode = .center
        chevron.frame = CGRect(x: cardInset + contentWidth - chevronSize,
                               y: y, width: chevronSize, height: headFit.height)
        placed.append(chevron)

        let headingRowHeight = headFit.height
        y += headingRowHeight

        if expanded {
            y += headingGap
            let entries = tipsEntries()
            for entry in entries {
                guard let iconName = entry["icon"] as? String,
                      let color = entry["color"] as? UIColor,
                      let title = entry["title"] as? String,
                      let body = entry["body"] as? String else { continue }
                let row = buildTipRow(icon: iconName, color: color,
                                      title: title, body: body, width: contentWidth)
                var f = row.frame
                f.origin = CGPoint(x: cardInset, y: y)
                row.frame = f
                placed.append(row)
                y += f.size.height + rowGap
            }
            y -= rowGap
        }

        y += cardInset

        let tap = UIButton(type: .custom)
        tap.backgroundColor = .clear
        let tapHeight = max(headingRowHeight, 44.0)
        tap.frame = CGRect(x: cardInset, y: cardInset, width: contentWidth, height: tapHeight)
        tap.addTarget(self, action: #selector(toggleTipsExpanded), for: .touchUpInside)
        placed.append(tap)

        let card = UIView(frame: CGRect(x: horizontalMargin, y: topPadding,
                                        width: width - horizontalMargin * 2, height: y))
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12.0
        card.layer.cornerCurve = .continuous
        for v in placed { card.addSubview(v) }

        let supportWidth = width - horizontalMargin * 2
        let signalBtn = buildSupportButton(title: "Join Signal Group",
                                           icon: "bubble.left.and.bubble.right.fill",
                                           background: .systemBlue,
                                           url: kSignalGroupURL,
                                           width: supportWidth,
                                           height: supportButtonHeight)
        var signalFrame = signalBtn.frame
        signalFrame.origin = CGPoint(x: horizontalMargin, y: card.frame.maxY + supportGap)
        signalBtn.frame = signalFrame

        let issuesBtn = buildSupportButton(title: "GitHub Issues",
                                           icon: "exclamationmark.bubble.fill",
                                           background: .systemIndigo,
                                           url: kGitHubIssuesURL,
                                           width: supportWidth,
                                           height: supportButtonHeight)
        var issuesFrame = issuesBtn.frame
        issuesFrame.origin = CGPoint(x: horizontalMargin, y: signalBtn.frame.maxY + supportButtonGap)
        issuesBtn.frame = issuesFrame

        let containerHeight = issuesBtn.frame.maxY + bottomPadding
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: containerHeight))
        container.addSubview(card)
        container.addSubview(signalBtn)
        container.addSubview(issuesBtn)

        tableView.tableHeaderView = container
    }

    @objc private func toggleTipsExpanded() {
        let ud = UserDefaults.standard
        ud.set(!ud.bool(forKey: kTipsExpandedDefault), forKey: kTipsExpandedDefault)
        installTipsHeader()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let hdr = tableView.tableHeaderView else { return }
        if abs(hdr.frame.size.width - tableView.bounds.size.width) > 0.5 {
            installTipsHeader()
        }
    }

    // MARK: - Search

    func updateSearchResults(for searchController: UISearchController) {
        let q = searchController.searchBar.text ?? ""
        guard q != searchText else { return }
        searchText = q
        rebuildFilteredData()
        tableView.reloadData()
    }

    // MARK: - Filtering / bucketing

    private func packageMatches(_ pkg: Package, query q: String) -> Bool {
        if q.isEmpty { return true }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if pkg.name.range(of: q, options: opts) != nil             { return true }
        if pkg.shortDescription.range(of: q, options: opts) != nil { return true }
        if pkg.category.range(of: q, options: opts) != nil         { return true }
        return false
    }

    private func rebuildFilteredData() {
        let filtered = allPackagesSorted.filter { packageMatches($0, query: searchText) }
        flatPackages = filtered

        guard groupByCategory else {
            visibleCategories = []
            packagesByCategory = [:]
            return
        }

        var cats: [String] = []
        var bucket: [String: [Package]] = [:]
        for cat in PackageCatalog.categoriesInOrder() {
            let inCat = filtered.filter { $0.category == cat }
            if !inCat.isEmpty {
                cats.append(cat)
                bucket[cat] = inCat
            }
        }
        visibleCategories = cats
        packagesByCategory = bucket
    }

    // MARK: - Data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return groupByCategory ? visibleCategories.count : 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if groupByCategory {
            let cat = visibleCategories[section]
            return packagesByCategory[cat]?.count ?? 0
        }
        return flatPackages.count
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 { return 26.0 }
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 0 else { return nil }
        guard let title = self.tableView(tableView, titleForHeaderInSection: section),
              !title.isEmpty else { return nil }

        let hdr = UIView()
        let lbl = UILabel()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel,
            .kern: 0.4 as CGFloat,
        ]
        lbl.attributedText = NSAttributedString(string: title.uppercased(), attributes: attrs)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        hdr.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: hdr.layoutMarginsGuide.leadingAnchor),
            lbl.trailingAnchor.constraint(equalTo: hdr.layoutMarginsGuide.trailingAnchor),
            lbl.bottomAnchor.constraint(equalTo: hdr.bottomAnchor, constant: -4.0),
        ])
        return hdr
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return groupByCategory ? visibleCategories[section] : nil
    }

    private func package(at indexPath: IndexPath) -> Package {
        if groupByCategory {
            let cat = visibleCategories[indexPath.section]
            return packagesByCategory[cat]![indexPath.row]
        }
        return flatPackages[indexPath.row]
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kPackageCellID)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: kPackageCellID)

        let pkg = package(at: indexPath)

        var config = UIListContentConfiguration.subtitleCell()
        config.image = UIImage(systemName: pkg.symbolName)
        config.imageProperties.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 22.0, weight: .regular)
        let mainColor: UIColor = pkg.isInstallDisabled ? .secondaryLabel : (view.tintColor ?? .systemBlue)
        config.imageProperties.tintColor        = mainColor
        config.imageProperties.reservedLayoutSize = CGSize(width: 34.0, height: 28.0)
        config.imageProperties.maximumSize      = CGSize(width: 28.0, height: 28.0)
        config.imageToTextPadding               = 14.0
        config.text = pkg.name
        config.textProperties.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        if pkg.isInstallDisabled { config.textProperties.color = .secondaryLabel }
        config.secondaryText = pkg.shortDescription
        config.secondaryTextProperties.color = pkg.isInstallDisabled ? .tertiaryLabel : .secondaryLabel
        config.secondaryTextProperties.numberOfLines = 2
        config.textToSecondaryTextVerticalPadding = 3.0
        var margins = config.directionalLayoutMargins
        margins.top    = 14.0
        margins.bottom = 14.0
        config.directionalLayoutMargins = margins
        cell.contentConfiguration = config

        cell.accessoryView = accessoryView(for: pkg)
        cell.accessoryType = cell.accessoryView != nil ? .none : .disclosureIndicator

        return cell
    }

    private func accessoryView(for pkg: Package) -> UIView? {
        let intent = PackageQueue.sharedQueue().intentForPackage(pkg)

        if pkg.kind == .DirectTool {
            return pill(text: "MANUAL",
                        background: UIColor.secondaryLabel.withAlphaComponent(0.14),
                        textColor: .secondaryLabel)
        }
        if pkg.kind == .OTA {
            if intent != .None {
                let text = intent == .Install ? "DISABLE PENDING" : "ENABLE PENDING"
                let color = view.tintColor ?? .systemBlue
                return pill(text: text,
                            background: color.withAlphaComponent(0.18),
                            textColor: color)
            }
            return pill(text: "MANUAL",
                        background: UIColor.secondaryLabel.withAlphaComponent(0.14),
                        textColor: .secondaryLabel)
        }
        if pkg.kind == .NanoRegistry {
            if intent != .None {
                let text = intent == .Install ? "APPLY PENDING" : "REMOVE PENDING"
                let color = view.tintColor ?? .systemBlue
                return pill(text: text,
                            background: color.withAlphaComponent(0.18),
                            textColor: color)
            }
            return pill(text: "MANUAL",
                        background: UIColor.secondaryLabel.withAlphaComponent(0.14),
                        textColor: .secondaryLabel)
        }
        if pkg.kind == .CallRecordingSound {
            if intent != .None {
                let text = intent == .Install ? "SILENCE PENDING" : "RESTORE PENDING"
                let color = view.tintColor ?? .systemBlue
                return pill(text: text,
                            background: color.withAlphaComponent(0.18),
                            textColor: color)
            }
            return pill(text: "MANUAL",
                        background: UIColor.secondaryLabel.withAlphaComponent(0.14),
                        textColor: .secondaryLabel)
        }
        if pkg.kind == .HideHomeBar {
            if intent != .None {
                let text = intent == .Install ? "HIDE PENDING" : "RESTORE PENDING"
                let color = view.tintColor ?? .systemBlue
                return pill(text: text,
                            background: color.withAlphaComponent(0.18),
                            textColor: color)
            }
            return pill(text: "MANUAL",
                        background: UIColor.secondaryLabel.withAlphaComponent(0.14),
                        textColor: .secondaryLabel)
        }
        if intent != .None {
            let text = intent == .Install ? "WILL ACTIVATE" : "WILL DEACTIVATE"
            let color = view.tintColor ?? .systemBlue
            return pill(text: text,
                        background: color.withAlphaComponent(0.18),
                        textColor: color)
        }
        if pkg.isInstalled {
            return pill(text: "INSTALLED",
                        background: UIColor(red: 0.16, green: 0.55, blue: 0.32, alpha: 0.18),
                        textColor: .systemGreen)
        }
        if pkg.isInstallDisabled {
            return pill(text: "DISABLED",
                        background: UIColor.systemRed.withAlphaComponent(0.16),
                        textColor: .systemRed)
        }
        if pkg.creatorOnly {
            return pill(text: "IN DEV",
                        background: UIColor.systemPurple.withAlphaComponent(0.16),
                        textColor: .systemPurple)
        }
        if pkg.experimental {
            return pill(text: "EXPERIMENTAL",
                        background: UIColor.systemRed.withAlphaComponent(0.18),
                        textColor: .systemRed)
        }
        if pkg.category.caseInsensitiveCompare("Beta") == .orderedSame {
            return pill(text: "BETA",
                        background: UIColor.systemPurple.withAlphaComponent(0.18),
                        textColor: .systemPurple)
        }
        if pkg.isNew {
            return pill(text: "NEW",
                        background: UIColor(red: 0.95, green: 0.55, blue: 0.05, alpha: 0.18),
                        textColor: .systemOrange)
        }
        return nil
    }

    private func pill(text: String, background: UIColor, textColor: UIColor) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 11.0, weight: .heavy)
        label.textColor = textColor
        label.backgroundColor = background
        label.textAlignment = .center
        label.sizeToFit()

        var frame = label.frame
        frame.size.width  += 14.0
        frame.size.height  = 22.0
        label.frame = frame

        label.layer.cornerRadius = frame.size.height / 2.0
        label.layer.cornerCurve = .continuous
        label.layer.masksToBounds = true
        return label
    }

    // MARK: - Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let pkg = package(at: indexPath)
        let detail = PackageDetailViewController(package: pkg)
        navigationController?.pushViewController(detail, animated: true)
    }

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {

        let pkg = package(at: indexPath)
        let q = PackageQueue.sharedQueue()
        let intent = q.intentForPackage(pkg)

        if pkg.kind == .DirectTool {
            let open = UIContextualAction(style: .normal, title: "Open") { [weak self] _, _, done in
                done(true)
                self?.navigateToSettingsSection(for: pkg)
            }
            open.backgroundColor = view.tintColor
            open.image = UIImage(systemName: "slider.horizontal.3")
            let cfg = UISwipeActionsConfiguration(actions: [open])
            cfg.performsFirstActionWithFullSwipe = true
            return cfg
        }

        if pkg.isInstallDisabled && !pkg.isInstalled && intent == .None { return nil }

        if pkg.kind == .OTA && intent == .None {
            let disable = UIContextualAction(style: .destructive, title: "Disable") { [weak self] _, _, done in
                guard let self = self else { done(true); return }
                if self.presentQueueConflictIfNeededForPackage(pkg, intent: .Install) { done(true); return }
                q.queueIntentForPackage(.Install, forPackage: pkg)
                done(true)
            }
            disable.image = UIImage(systemName: "icloud.slash")

            let enable = UIContextualAction(style: .normal, title: "Enable") { [weak self] _, _, done in
                guard let self = self else { done(true); return }
                if self.presentQueueConflictIfNeededForPackage(pkg, intent: .Uninstall) { done(true); return }
                q.queueIntentForPackage(.Uninstall, forPackage: pkg)
                done(true)
            }
            enable.backgroundColor = .systemGreen
            enable.image = UIImage(systemName: "icloud")

            let cfg = UISwipeActionsConfiguration(actions: [disable, enable])
            cfg.performsFirstActionWithFullSwipe = false
            return cfg
        }

        if pkg.kind == .NanoRegistry && intent == .None {
            let apply = UIContextualAction(style: .normal, title: "Apply") { [weak self] _, _, done in
                guard let self = self else { done(true); return }
                if self.presentQueueConflictIfNeededForPackage(pkg, intent: .Install) { done(true); return }
                q.queueIntentForPackage(.Install, forPackage: pkg)
                done(true)
            }
            apply.backgroundColor = view.tintColor
            apply.image = UIImage(systemName: "applewatch.radiowaves.left.and.right")

            let remove = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
                guard let self = self else { done(true); return }
                if self.presentQueueConflictIfNeededForPackage(pkg, intent: .Uninstall) { done(true); return }
                q.queueIntentForPackage(.Uninstall, forPackage: pkg)
                done(true)
            }
            remove.image = UIImage(systemName: "xmark.circle")

            let cfg = UISwipeActionsConfiguration(actions: [apply, remove])
            cfg.performsFirstActionWithFullSwipe = false
            return cfg
        }

        if pkg.kind == .CallRecordingSound && intent == .None {
            let silence = UIContextualAction(style: .destructive, title: "Silence") { [weak self] _, _, done in
                guard let self = self else { done(true); return }
                done(true)
                PackageDetailViewController.presentCallRecordingDisclosureIfNeeded(
                    from: self) {
                    if self.presentQueueConflictIfNeededForPackage(pkg, intent: .Install) { return }
                    q.queueIntentForPackage(.Install, forPackage: pkg)
                }
            }
            silence.image = UIImage(systemName: "speaker.slash.fill")

            let restore = UIContextualAction(style: .normal, title: "Restore") { [weak self] _, _, done in
                guard let self = self else { done(true); return }
                if self.presentQueueConflictIfNeededForPackage(pkg, intent: .Uninstall) { done(true); return }
                q.queueIntentForPackage(.Uninstall, forPackage: pkg)
                done(true)
            }
            restore.backgroundColor = .systemGreen
            restore.image = UIImage(systemName: "speaker.wave.2.fill")

            let cfg = UISwipeActionsConfiguration(actions: [silence, restore])
            cfg.performsFirstActionWithFullSwipe = false
            return cfg
        }

        if pkg.kind == .HideHomeBar && intent == .None {
            let hide = UIContextualAction(style: .destructive, title: "Hide") { [weak self] _, _, done in
                guard let self = self else { done(true); return }
                if self.presentQueueConflictIfNeededForPackage(pkg, intent: .Install) { done(true); return }
                q.queueIntentForPackage(.Install, forPackage: pkg)
                done(true)
            }
            hide.image = UIImage(systemName: "line.3.horizontal")

            let restore = UIContextualAction(style: .normal, title: "Restore") { [weak self] _, _, done in
                guard let self = self else { done(true); return }
                if self.presentQueueConflictIfNeededForPackage(pkg, intent: .Uninstall) { done(true); return }
                q.queueIntentForPackage(.Uninstall, forPackage: pkg)
                done(true)
            }
            restore.backgroundColor = .systemGreen
            restore.image = UIImage(systemName: "arrow.clockwise")

            let cfg = UISwipeActionsConfiguration(actions: [hide, restore])
            cfg.performsFirstActionWithFullSwipe = false
            return cfg
        }

        let title: String
        let color: UIColor
        let symbol: String
        if intent != .None {
            title  = "Cancel"
            color  = .systemGray
            symbol = "xmark.circle"
        } else if pkg.isInstalled {
            title  = "Deactivate"
            color  = .systemRed
            symbol = "power"
        } else if packageNeedsThemeBeforeInstall(pkg) {
            title  = "Select Theme"
            color  = view.tintColor ?? .systemBlue
            symbol = "paintpalette"
        } else if packageNeedsLiveWPVideoBeforeInstall(pkg) {
            title  = "Select Video"
            color  = view.tintColor ?? .systemBlue
            symbol = "photo.badge.plus"
        } else {
            title  = "Activate"
            color  = view.tintColor ?? .systemBlue
            symbol = "play.circle"
        }

        let action = UIContextualAction(style: .normal, title: title) { [weak self] _, _, done in
            guard let self = self else { done(true); return }
            let isInstall   = intent == .None && !pkg.isInstalled
            let isUninstall = intent == .None && pkg.isInstalled
            if isInstall && self.packageNeedsThemeBeforeInstall(pkg) {
                done(true)
                self.presentThemeRequiredAlert(for: pkg)
                return
            }
            if isInstall && self.packageNeedsLiveWPVideoBeforeInstall(pkg) {
                done(true)
                self.navigateToSettingsSection(for: pkg)
                return
            }
            if isInstall && self.presentQueueConflictIfNeededForPackage(pkg, intent: .Install) {
                done(true)
                return
            }
            if isUninstall && self.presentQueueConflictIfNeededForPackage(pkg, intent: .Uninstall) {
                done(true)
                return
            }
            q.toggleForPackage(pkg)
            done(true)
        }
        action.backgroundColor = color
        action.image = UIImage(systemName: symbol)

        let cfg = UISwipeActionsConfiguration(actions: [action])
        cfg.performsFirstActionWithFullSwipe = true
        return cfg
    }

    private func presentThemeRequiredAlert(for pkg: Package) {
        let alert = UIAlertController(
            title: "Select a Theme",
            message: "Icon themes need a selected theme before they can be activated. Choose iOS 6 Theme or import a custom theme first.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Open Theme Settings", style: .default) { [weak self] _ in
            self?.navigateToSettingsSection(for: pkg)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true)
    }

    private func navigateToSettingsSection(for pkg: Package) {
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
        guard let bundle = SettingsViewController(underlyingSection: pkg.settingsSection,
                                                  bundleTitle: pkg.name) else { return }
        bundle.installerReturnPackageName = pkg.name
        nav.pushViewController(bundle, animated: false)
        tab.selectedIndex = idx
    }

    private func presentConfigureAlert(for pkg: Package) {
        let msg = "\(pkg.name) has configurable options. Set them up first so the tweak applies with your preferences on the first activation."
        let alert = UIAlertController(title: "Customize Before Activating?",
                                      message: msg,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Configure First", style: .default) { [weak self] _ in
            let detail = PackageDetailViewController(package: pkg)
            self?.navigationController?.pushViewController(detail, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Activate Anyway", style: .default) { [weak self] _ in
            guard let self = self else { return }
            if self.presentQueueConflictIfNeededForPackage(pkg, intent: .Install) { return }
            PackageQueue.sharedQueue().toggleForPackage(pkg)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true)
    }
}
