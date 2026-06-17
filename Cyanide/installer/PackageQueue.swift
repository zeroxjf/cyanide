//
//  PackageQueue.swift
//  Cyanide
//
//  Sileo-style install/uninstall queue. User taps Install/Uninstall in a
//  package detail page; nothing applies until commit() is called from the
//  Queue review screen.
//

import Foundation

@objc public enum PackageQueueIntent: Int {
    case None = 0
    case Install
    case Uninstall
}

@objc public class PackageQueue: NSObject {
    @objc public static let didChangeNotification: String = "PackageQueueDidChangeNotification"

    private var installs: NSMutableArray = NSMutableArray()
    private var uninstalls: NSMutableArray = NSMutableArray()

    @objc public static func shared() -> PackageQueue {
        return _shared
    }

    // ObjC-compatible selector: +sharedQueue
    @objc(sharedQueue)
    public static func sharedQueue() -> PackageQueue {
        return _shared
    }

    private static let _shared = PackageQueue()

    override init() {
        super.init()
    }

    @objc public var queuedInstalls: [Package] {
        var out = installs.compactMap { $0 as? Package }
        if hasExplicitHideHomeBarQueued {
            return out.filter { $0.kind == .HideHomeBar }
        }
        for p in PackageCatalog.allPackages() {
            if p.isInstallDisabled { continue }
            if !packageCanQueueInstall(p) { continue }
            if !p.isQueuedForApply { continue }
            if packageInArray(out, matching: p) != nil { continue }
            if packageInArray(uninstalls.compactMap { $0 as? Package }, matching: p) != nil { continue }
            out.append(p)
        }
        return out
    }

    @objc public var queuedUninstalls: [Package] {
        if !hasExplicitHideHomeBarQueued {
            return uninstalls.compactMap { $0 as? Package }
        }
        return uninstalls.compactMap { $0 as? Package }.filter { $0.kind == .HideHomeBar }
    }

    @objc public var pendingCount: Int {
        return queuedInstalls.count + queuedUninstalls.count
    }

    @objc public func intent(for package: Package) -> PackageQueueIntent {
        if package.kind == .DirectTool { return .None }
        let hideHomeBarQueued = hasExplicitHideHomeBarQueued
        let isHideHomeBar = package.kind == .HideHomeBar
        if hideHomeBarQueued && !isHideHomeBar { return .None }
        if !package.isInstalled && !packageCanQueueInstall(package) { return .None }
        if packageInArray(installs.compactMap { $0 as? Package }, matching: package) != nil { return .Install }
        if packageInArray(uninstalls.compactMap { $0 as? Package }, matching: package) != nil { return .Uninstall }
        if package.isInstallDisabled { return .None }
        if package.isQueuedForApply { return .Install }
        return .None
    }

    // ObjC-compatible selector: -intentForPackage:
    @objc(intentForPackage:)
    public func intentForPackage(_ package: Package) -> PackageQueueIntent {
        return intent(for: package)
    }

    @objc public func canQueue(_ intent: PackageQueueIntent,
                               for package: Package,
                               reason: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        reason?.pointee = nil
        if intent == .None { return true }
        let isHideHomeBar = package.kind == .HideHomeBar
        if isHideHomeBar && pendingCountExcluding(package) > 0 {
            reason?.pointee = "Hide Home Bar changes the system home-indicator asset and needs a respring right after. Clear the current queue, run Hide Home Bar by itself, respring, then queue your other tweaks." as NSString
            return false
        }
        if !isHideHomeBar && hasQueuedHideHomeBarIntentExcluding(package) {
            reason?.pointee = "Hide Home Bar is already waiting in the queue and must run by itself. Apply or remove Hide Home Bar first, then queue other tweaks after the respring." as NSString
            return false
        }
        return true
    }

    // ObjC-compatible selector: -canQueueIntent:forPackage:reason:
    @objc(canQueueIntent:forPackage:reason:)
    public func canQueueIntent(_ intent: PackageQueueIntent,
                               forPackage package: Package,
                               reason: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        return canQueue(intent, for: package, reason: reason)
    }

    // Sileo-style "tap toggles queue":
    //   not installed + not queued  → queue install
    //   not installed + queued      → cancel queue
    //   installed     + not queued  → queue uninstall
    //   installed     + queued      → cancel queue
    @objc public func toggle(for package: Package) {
        let current = intent(for: package)
        if current != .None {
            remove(package)
            return
        }
        if package.isInstallDisabled && !package.isInstalled { return }
        if !package.isInstalled && !packageCanQueueInstall(package) { return }
        let nextIntent: PackageQueueIntent = package.isInstalled ? .Uninstall : .Install
        if !canQueue(nextIntent, for: package, reason: nil) { return }

        if package.isInstalled {
            uninstalls.add(package)
        } else {
            installs.add(package)
        }
        notifyChange()
    }

    // ObjC-compatible selector: -toggleForPackage:
    @objc(toggleForPackage:)
    public func toggleForPackage(_ package: Package) {
        toggle(for: package)
    }

    @objc public func queueIntent(_ intent: PackageQueueIntent, for package: Package) {
        if !canQueue(intent, for: package, reason: nil) { return }
        remove(package)
        if intent == .Install {
            if !packageCanQueueInstall(package) { return }
            installs.add(package)
        } else if intent == .Uninstall {
            uninstalls.add(package)
        }
        notifyChange()
    }

    // ObjC-compatible selector: -queueIntent:forPackage:
    @objc(queueIntent:forPackage:)
    public func queueIntentForPackage(_ intent: PackageQueueIntent, forPackage package: Package) {
        queueIntent(intent, for: package)
    }

    @objc public func remove(_ package: Package) {
        if let match = packageInArray(installs.compactMap { $0 as? Package }, matching: package) {
            installs.remove(match)
        }
        if let match = packageInArray(uninstalls.compactMap { $0 as? Package }, matching: package) {
            uninstalls.remove(match)
        }
        if package.isQueuedForApply {
            package.applyCommittedState(false)
        }
        notifyChange()
    }

    // ObjC-compatible selector: -removePackage:
    @objc(removePackage:)
    public func removePackage(_ package: Package) {
        remove(package)
    }

    @objc public func clear() {
        // Always fire notifyChange — observers like QueuePopupBar drive their
        // visibility off pendingCount and need a kick to re-evaluate when the
        // queue empties (e.g. after Reset All Packages drained the isQueuedForApply
        // packages via applyCommittedState:NO before clear() got a chance to act).
        let queuedForApply = queuedInstalls
        let installsArr = installs.compactMap { $0 as? Package }
        for pkg in queuedForApply {
            if packageInArray(installsArr, matching: pkg) == nil && pkg.isQueuedForApply {
                pkg.applyCommittedState(false)
            }
        }
        installs.removeAllObjects()
        uninstalls.removeAllObjects()
        notifyChange()
    }

    // Writes the persisted state for every queued package, then triggers
    // settings_run_pending_actions() once. Clears the queue afterwards.
    @objc public func commit() {
        let toInstall = queuedInstalls
        let toUninstall = queuedUninstalls

        var heavyInstalls: [Package] = []
        var heavyUninstalls: [Package] = []
        var needsRunActions = false

        for pkg in toInstall {
            if pkg.kind == .Toggle {
                needsRunActions = true
                pkg.applyCommittedState(true)
            } else {
                heavyInstalls.append(pkg)
            }
        }
        for pkg in toUninstall {
            if pkg.kind == .Toggle {
                needsRunActions = true
                pkg.applyCommittedState(false)
            } else {
                heavyUninstalls.append(pkg)
            }
        }

        installs.removeAllObjects()
        uninstalls.removeAllObjects()
        notifyChange()

        let hasHeavy = !heavyInstalls.isEmpty || !heavyUninstalls.isEmpty

        if !hasHeavy {
            if needsRunActions {
                settings_run_pending_actions()
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .settingsActionsDidComplete,
                        object: nil)
                }
            }
            return
        }

        let _needsRunActions = needsRunActions
        DispatchQueue.global(qos: .userInitiated).async {
            for pkg in heavyInstalls   { pkg.applyCommittedState(true) }
            for pkg in heavyUninstalls { pkg.applyCommittedState(false) }
            DispatchQueue.main.async {
                if _needsRunActions {
                    settings_run_pending_actions()
                } else {
                    NotificationCenter.default.post(
                        name: .settingsActionsDidComplete,
                        object: nil)
                }
            }
        }
    }

    // MARK: - Private helpers

    private func packageCanQueueInstall(_ package: Package) -> Bool {
        if package.kind == .DirectTool { return false }
        if package.identifier != "com.darksword.themer" { return true }
        return settings_themer_has_selected_theme()
    }

    private func packageInArray(_ array: [Package], matching package: Package) -> Package? {
        return array.first { $0.identifier == package.identifier }
    }

    private var hasExplicitHideHomeBarQueued: Bool {
        let installsArr = installs.compactMap { $0 as? Package }
        let uninstallsArr = uninstalls.compactMap { $0 as? Package }
        return installsArr.contains { $0.kind == .HideHomeBar }
            || uninstallsArr.contains { $0.kind == .HideHomeBar }
    }

    private func pendingCountExcluding(_ package: Package) -> Int {
        var count = 0
        for p in queuedInstalls   { if p.identifier != package.identifier { count += 1 } }
        for p in queuedUninstalls { if p.identifier != package.identifier { count += 1 } }
        return count
    }

    private func hasQueuedHideHomeBarIntentExcluding(_ package: Package) -> Bool {
        let installsArr = installs.compactMap { $0 as? Package }
        let uninstallsArr = uninstalls.compactMap { $0 as? Package }
        if installsArr.contains(where: { $0.identifier != package.identifier && $0.kind == .HideHomeBar }) { return true }
        if uninstallsArr.contains(where: { $0.identifier != package.identifier && $0.kind == .HideHomeBar }) { return true }
        return false
    }

    private func notifyChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name(rawValue: "PackageQueueDidChangeNotification"),
            object: self)
    }
}
