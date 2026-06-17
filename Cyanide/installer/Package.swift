//
//  Package.swift
//  Cyanide
//
//  Model object representing one tweak in the Installer-style packages tab.
//

import Foundation

@objc public enum PackageInstallKind: Int {
    // Master enable is a BOOL in NSUserDefaults under enabledKey. Installing
    // sets it to YES; uninstalling sets NO. settings_run_actions() applies.
    case Toggle = 0

    // Persistent system tweak that does not use settings_run_actions().
    // Installing calls darksword_ota_set_disabled(true); uninstalling calls
    // darksword_ota_set_disabled(false). State tracked in a defaults intent key.
    case OTA = 1

    // One-shot plist edit gated by kexploit + sandbox patch (NanoRegistry
    // watchOS pairing-compatibility override). Installing calls
    // settings_apply_nano_registry_now(YES) which writes the four
    // compatibility keys from the Settings bundle; uninstalling clears them.
    // No live RC loop, doesn't run settings_run_actions.
    case NanoRegistry = 2

    // One-shot CallServices audio replacement gated by kexploit + sandbox
    // patch. Installing writes bundled silent disclosure sounds and stores
    // the first originals in Cyanide's app container; uninstalling restores
    // those backups when present.
    case CallRecordingSound = 3

    // One-shot DirtyZero-style MaterialKit asset page zero. Installing hides
    // the home bar after respring; restoring needs a respring.
    case HideHomeBar = 4

    // Direct settings tool. It has a Settings bundle but no install queue,
    // active state, or PackageQueue commit step.
    case DirectTool = 5
}

@objc public class Package: NSObject {
    @objc public let identifier: String
    @objc public let name: String
    @objc public let shortDescription: String
    @objc public let longDescription: String
    @objc public let version: String
    @objc public let author: String
    @objc public let category: String
    @objc public let symbolName: String
    @objc public let kind: PackageInstallKind
    @objc public let enabledKey: String?
    @objc public let isNew: Bool

    // SettingsSection enum value that corresponds to this package's bundle in the
    // Settings tab. NSIntegerMax means the package has no Settings bundle
    // (install/uninstall is its only operation).
    @objc public var settingsSection: Int = Int.max

    // If non-nil, the detail view renders this text as a red disclaimer banner
    // above the Information card.
    @objc public var unstableWarning: String?

    // Non-nil means users can view the package and uninstall an existing install,
    // but cannot queue a fresh install until the reason is cleared.
    @objc public var installDisabledReason: String?

    // YES means the package is gated behind kSettingsExperimentalTweaksEnabled.
    @objc public var experimental: Bool = false

    // YES means the package is only installable by the campaign creator.
    @objc public var creatorOnly: Bool = false

    // Non-nil means the package detail view shows a prominent "Known Issues" card.
    @objc public var knownIssues: [String]?

    @objc public var isInstalled: Bool {
        let d = UserDefaults.standard
        switch kind {
        case .Toggle:
            guard let key = enabledKey else { return false }
            return d.bool(forKey: key)
        case .OTA, .NanoRegistry, .CallRecordingSound, .HideHomeBar, .DirectTool:
            return false
        @unknown default:
            return false
        }
    }

    @objc public var isQueuedForApply: Bool {
        guard kind == .Toggle, let key = enabledKey else { return false }
        if isInstallDisabled { return false }
        return UserDefaults.standard.bool(forKey: key) && !settings_tweak_is_applied(key)
    }

    @objc public var isInstallDisabled: Bool {
        if let reason = installDisabledReason, !reason.isEmpty { return true }
        if experimental {
            let experimentalOn = UserDefaults.standard.bool(forKey: kSettingsExperimentalTweaksEnabled)
            if !experimentalOn || !(cyanide_is_patron() || cyanide_is_creator()) { return true }
        }
        if creatorOnly && !cyanide_is_creator() { return true }
        return false
    }

    @objc public init(identifier: String,
                      name: String,
                      shortDescription: String,
                      longDescription: String,
                      version: String,
                      author: String,
                      category: String,
                      symbolName: String,
                      kind: PackageInstallKind,
                      enabledKey: String?,
                      isNew: Bool) {
        self.identifier = identifier
        self.name = name
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.version = version
        self.author = author
        self.category = category
        self.symbolName = symbolName
        self.kind = kind
        self.enabledKey = enabledKey
        self.isNew = isNew
    }

    @objc public func install()   { PackageQueue.shared().toggle(for: self) }
    @objc public func uninstall() { PackageQueue.shared().toggle(for: self) }

    // Called by PackageQueue.commit — writes the persisted state without
    // triggering settings_run_actions itself (the queue does that once).
    @objc public func applyCommittedState(_ installed: Bool) {
        let d = UserDefaults.standard
        switch kind {
        case .Toggle:
            if let key = enabledKey {
                d.set(installed, forKey: key)
                d.synchronize()
            }
        case .OTA:
            if settings_apply_ota_disabled(installed) {
                cyanide_log("[INSTALLER] OTA updates \(installed ? "disabled" : "enabled").\n")
            } else {
                cyanide_log("[INSTALLER] OTA \(installed ? "disable" : "enable") failed; install state was not changed.\n")
            }
        case .NanoRegistry:
            if settings_apply_nano_registry_now(installed) {
                cyanide_log("[INSTALLER] Watch pairing override \(installed ? "applied" : "removed").\n")
            } else {
                cyanide_log("[INSTALLER] Watch pairing override \(installed ? "apply" : "remove") failed; state was not changed.\n")
            }
        case .CallRecordingSound:
            if settings_apply_call_recording_sound_disabled(installed) {
                cyanide_log("[INSTALLER] Call recording disclosure sound \(installed ? "silenced" : "restored").\n")
            } else {
                cyanide_log("[INSTALLER] Call recording disclosure sound \(installed ? "silence" : "restore") failed.\n")
            }
        case .HideHomeBar:
            if settings_apply_hide_home_bar_hidden(installed) {
                cyanide_log("[INSTALLER] Home bar \(installed ? "hidden; respring to apply" : "restore queued; respring to apply").\n")
            } else {
                cyanide_log("[INSTALLER] Home bar \(installed ? "hide" : "restore") failed.\n")
            }
        case .DirectTool:
            break
        @unknown default:
            break
        }
    }
}
