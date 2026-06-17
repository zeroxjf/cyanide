//
//  PackageCatalog.swift
//  Cyanide
//
//  Static catalog of installable packages (one per user-facing tweak).
//

import Foundation

@objc public class PackageCatalog: NSObject {

    // Flat list, in display order. Filtered by the master experimental gate —
    // packages with `experimental == YES` are omitted unless
    // kSettingsExperimentalTweaksEnabled is on.
    @objc public static func allPackages() -> [Package] {
        let full = allPackagesIncludingExperimental()
        let creator = cyanide_is_creator()
        let experimentalAccess = cyanide_is_patron() || creator
        let experimentalOn = UserDefaults.standard.bool(forKey: kSettingsExperimentalTweaksEnabled)
            && experimentalAccess
        return full.filter { p in
            if p.creatorOnly && !creator { return false }
            if p.experimental && !experimentalOn { return false }
            return true
        }
    }

    // Full list, ignoring the experimental gate. Use only for internal lookups
    // (e.g. translating an identifier the user previously installed back into a
    // Package even after they flip the master switch off). Never render this
    // list directly.
    @objc public static func allPackagesIncludingExperimental() -> [Package] {
        return _allPackages
    }

    private static let _allPackages: [Package] = buildPackageList()

    // Section header order, derived from allPackages.
    @objc public static func categoriesInOrder() -> [String] {
        let preferred = [
            "In Development",
            "Experimental",
            "Beta",
            "Status Bar",
            "Home Screen Layout",
            "Other Tweaks",
            "Performance",
            "System Updates",
            "System",
            "SpringBoard Tweaks",
        ]
        var all: [String] = []
        for p in allPackages() {
            if !all.contains(p.category) { all.append(p.category) }
        }
        var order: [String] = []
        for cat in preferred {
            if all.contains(cat) { order.append(cat) }
        }
        for cat in all {
            if !order.contains(cat) { order.append(cat) }
        }
        return order
    }

    // Packages bucketed by category in section order.
    @objc public static func packagesByCategory() -> [String: [Package]] {
        var buckets: [String: [Package]] = [:]
        for p in allPackages() {
            buckets[p.category, default: []].append(p)
        }
        return buckets
    }

    // MARK: - Package list builder

    private static func buildPackageList() -> [Package] {
        let version = "1.0"
        let privateAvailable = cyanide_private_tweaks_compiled_in()

        let statBar = Package(
            identifier: "com.darksword.statbar",
            name: "StatBar",
            shortDescription: "Battery temperature + free RAM overlay",
            longDescription: "Installs an overlay window in SpringBoard that shows live battery temperature and free RAM next to the system status bar. Refresh timing is adjustable so you can trade live updates for battery life.\n\nConfigure units, visible metrics, and refresh speed in the Settings tab.",
            version: version,
            author: "zeroxjf",
            category: "Status Bar",
            symbolName: "thermometer.medium",
            kind: .Toggle,
            enabledKey: kSettingsStatBarEnabled,
            isNew: false)
        statBar.settingsSection = 5 // SectionStatBar

        let nsBar = Package(
            identifier: "com.darksword.nsbar",
            name: "NSBar",
            shortDescription: "Network speed overlay in the status bar",
            longDescription: "Displays real-time download and upload speed in a compact SpringBoard status-bar overlay. Pick its corner or center position in Settings.\n\nPorted from d1y/cyanide-ios.",
            version: version,
            author: "d1y",
            category: "Status Bar",
            symbolName: "network",
            kind: .Toggle,
            enabledKey: kSettingsNSBarEnabled,
            isNew: true)
        nsBar.settingsSection = 6 // SectionNSBar

        let niceBarLite = Package(
            identifier: "com.darksword.nicebarlite",
            name: "NiceBar Lite",
            shortDescription: "NiceBar-style status labels",
            longDescription: "Adds configurable text labels around the status bar. Slots can show custom text, date/time formats, and system values such as battery, memory, network speed, uptime, IP address, disk space, thermal state, and traffic counters.\n\nPorted from d1y/cyanide-ios.",
            version: version,
            author: "d1y",
            category: "Status Bar",
            symbolName: "textformat.size",
            kind: .Toggle,
            enabledKey: kSettingsNiceBarLiteEnabled,
            isNew: true)
        niceBarLite.settingsSection = 7 // SectionNiceBarLite

        var signal: Package? = nil
        if privateAvailable {
            let s = Package(
                identifier: "com.darksword.rssidisplay",
                name: "Signal Readouts",
                shortDescription: "RSRP dBm on cellular, bar count on WiFi",
                longDescription: "Replaces the signal-strength glyphs in the status bar with live numeric readouts: RSRP in dBm for cellular, and the active bar count for WiFi. Updates roughly once per second.\n\nToggle WiFi-only or cellular-only in the Settings tab.",
                version: version,
                author: "zeroxjf",
                category: "In Development",
                symbolName: "antenna.radiowaves.left.and.right",
                kind: .Toggle,
                enabledKey: kSettingsRSSIDisplayEnabled,
                isNew: false)
            s.settingsSection = 8 // SectionRSSI
            s.experimental = true
            s.creatorOnly = true
            s.unstableWarning = "⚠️ In development — may not work at all. The live status-bar refresh interferes with other SpringBoard tweaks and can drop readouts entirely."
            signal = s
        }

        let sbc = Package(
            identifier: "com.darksword.sbcustomizer",
            name: "SBCustomizer",
            shortDescription: "Custom dock count and home screen grid",
            longDescription: "Customizes the dock icon count and the home screen icon grid (columns and rows). Optionally hides icon labels.\n\nAdjust the per-axis counts and the label-hide switch in the Settings tab.",
            version: version,
            author: "zeroxjf",
            category: "Home Screen Layout",
            symbolName: "square.grid.3x3.fill",
            kind: .Toggle,
            enabledKey: kSettingsSBCEnabled,
            isNew: false)
        sbc.settingsSection = 4 // SectionSBC

        let powercuff = Package(
            identifier: "com.darksword.powercuff",
            name: "Powercuff",
            shortDescription: "Underclock the CPU/GPU thermal pressure",
            longDescription: "Drives thermalmonitord with synthetic thermal pressure to underclock the CPU and GPU. Useful for cooling-sensitive workloads or extending runtime under load. Effects persist until reboot.\n\nNominal is the daily-use default. Light, Moderate, and Heavy intentionally underclock the CPU more, so lag and slower app launches mean it is working as intended. Those levels can be too slow for comfortable day-to-day use, especially on older devices.\n\nPick a level in the Settings tab.",
            version: version,
            author: "rpetrich",
            category: "Performance",
            symbolName: "bolt.slash.fill",
            kind: .Toggle,
            enabledKey: kSettingsPowercuffEnabled,
            isNew: false)
        powercuff.settingsSection = 12 // SectionPowercuff

        let axon = Package(
            identifier: "com.darksword.axonlite",
            name: "Axon Lite",
            shortDescription: "Group Notification Center requests by app",
            longDescription: "Groups visible Notification Center requests by app in a SpringBoard overlay and filters duplicates while Cyanide keeps the RemoteCall session alive.\n\nNo extra configuration.",
            version: version,
            author: "zeroxjf",
            category: "Beta",
            symbolName: "bell.badge.fill",
            kind: .Toggle,
            enabledKey: kSettingsAxonLiteEnabled,
            isNew: true)
        axon.unstableWarning = "⚠️ Experimental: work-in-progress. Expect SpringBoard crashes, dropped notifications, layout glitches, and breakage between Cyanide builds. Don't rely on it for anything important."

        var typeBanner: Package? = nil
        var notificationIsland: Package? = nil
        var ipaDecryptor: Package? = nil
        var stageStrip: Package? = nil
        if privateAvailable {
            let tb = Package(
                identifier: "com.darksword.typebanner",
                name: "TypeBanner",
                shortDescription: "iMessage typing banner under the Dynamic Island",
                longDescription: "Port of TypeMillennium. Shows a pill banner just below the Dynamic Island when imagent reports an active iMessage typing indicator.\n\nNo extra configuration.",
                version: version,
                author: "zeroxjf",
                category: "In Development",
                symbolName: "ellipsis.bubble.fill",
                kind: .Toggle,
                enabledKey: kSettingsTypeBannerEnabled,
                isNew: true)
            tb.experimental = true
            tb.settingsSection = 10 // SectionTypeBanner
            tb.creatorOnly = true
            tb.unstableWarning = "⚠️ In development — extremely unstable. Keeps an original-thread imagent RemoteCall session for live polling and may miss indicators or destabilize SpringBoard."
            typeBanner = tb

            let ni = Package(
                identifier: "com.darksword.notificationisland",
                name: "Notification Island",
                shortDescription: "Mirror incoming banners into the Dynamic Island",
                longDescription: "Experimental Dynamic Island notification route. Watches SpringBoard's active banner request over the shared RemoteCall session, then mirrors the title/body into Cyanide's ActivityKit Live Activity.\n\nNo extra configuration.",
                version: version,
                author: "zeroxjf",
                category: "In Development",
                symbolName: "bell.and.waves.left.and.right.fill",
                kind: .Toggle,
                enabledKey: kSettingsNotificationIslandEnabled,
                isNew: true)
            ni.settingsSection = 11 // SectionNotificationIsland
            ni.experimental = true
            ni.creatorOnly = true
            ni.unstableWarning = "⚠️ In development — polls SpringBoard notification state over RemoteCall and may miss banners, duplicate activity updates, or destabilize SpringBoard."
            notificationIsland = ni

            let ipa = Package(
                identifier: "com.darksword.ipadecryptor",
                name: "IPA Decryptor",
                shortDescription: "Decrypt installed App Store app payloads",
                longDescription: "In-development local IPA decryptor. Select an installed user app or paste an App Store link, resolve it to a bundle ID, sign in for an App Store download token, fetch the encrypted IPA to Documents, probe FairPlay encryption metadata, then run the decrypt pipeline.\n\nCurrent build wires app discovery, App Store link resolution, sign-in, encrypted IPA fetching, and encryption probing first. SINF/iTunesMetadata patching, decrypted page dumping, and rebuilding the Payload IPA are being added behind this same settings tool.",
                version: version,
                author: "londek / zeroxjf",
                category: "In Development",
                symbolName: "lock.open.fill",
                kind: .DirectTool,
                enabledKey: nil,
                isNew: true)
            ipa.settingsSection = 23 // SectionIPADecryptor
            ipa.experimental = true
            ipa.creatorOnly = true
            ipa.unstableWarning = "⚠️ In development — encrypted IPA download is experimental. SINF/iTunesMetadata patching, task-port dump, and IPA writer stages are not finished yet."
            ipaDecryptor = ipa

            let ss = Package(
                identifier: "com.darksword.stagestrip",
                name: "Dynamic Stage Lite",
                shortDescription: "Two floating app windows, iPad-style",
                longDescription: "Run two apps as floating, resizable windows on top of SpringBoard.\n\n"
                    + "Based on Dynamic Stage by tomt000 — the original Stage Manager-for-iPhone tweak. Dynamic Stage Lite is an independent, RemoteCall-only re-implementation of the split-view + scene-hosting design; no original tweak code or assets are reused. Go check out tomt000's full version on Havoc.\n\n"
                    + "How to use:\n"
                    + "• Tap the dot in the bottom-right corner of the screen to open the picker.\n"
                    + "• Tap two apps to launch them side-by-side.\n"
                    + "• Drag the top bar to move; drag any corner to resize.\n"
                    + "• X in the top-left of a window closes it.\n"
                    + "• Gear in the picker tray jumps back to Cyanide settings.\n\n"
                    + "First Run is slow. The picker has to enumerate every installed app over RemoteCall and build a tile per app — expect 1-2 minutes on a fresh install. Re-Runs reuse the cache and are fast.\n\n"
                    + "Rough edges:\n"
                    + "• Touch routing into hosted apps isn't wired — windows are for viewing/switching, not scrolling or typing.\n"
                    + "• Auto-close on full-screen launch is not yet hooked up; close manually with the X.\n"
                    + "• Gestures may stutter while the App Library is still filling in.",
                version: version,
                author: "zeroxjf",
                category: "Experimental",
                symbolName: "sidebar.left",
                kind: .Toggle,
                enabledKey: kSettingsStageStripEnabled,
                isNew: true)
            ss.experimental = true
            ss.unstableWarning = "⚠️ Early development. First Run takes 1-2 minutes because the picker enumerates every installed app and builds a tile per app. Re-Runs are fast. Touch routing into hosted windows isn't wired yet, so scrolling/typing inside a floating window may not work."
            stageStrip = ss
        }

        let locationSim = Package(
            identifier: "com.darksword.locationsim",
            name: "Location Simulator",
            shortDescription: "CoreLocation static point simulation",
            longDescription: "Spoofs the device's GPS location via Apple's CLSimulationManager. Requires Apple Maps installed and set up — Maps is the RemoteCall host process that drives the simulation.\n\nThis is a manual tool, not an installable package. Open Controls, choose a target, then use Simulate Current Target or Restore Real Location. Each run opens the activity log and marks completion when the request returns. Reset may take a few minutes and may require a reboot plus extra wait time.\n\nSettings exposes the current target plus altitude and accuracy. v1 is static-point only; route playback and alternate daemon hosts are next.\n\nNot all apps respect the simulated location. Apps that use their own location validation or additional signals may ignore it.\n\nCredits: kolbicz provided the GPS spoofer RemoteCall/CLSimulationManager prototype this is based on. ezzuldinSt's LSpoof provided the app-side CLLocationManager spoofing, picker, bookmarks, and route-simulation reference.\n\nSystem-behavior warning: simulated locations can affect more than maps. Features tied to location, including time zone, date/time behavior, weather, automation, reminders, and service checks, may behave unexpectedly. Only use this if you know what you're doing.\n\nLegal and service-use note: simulated locations may violate app terms, platform rules, game rules, ride-share or delivery policies, or local law depending on how they are used. Use only where you have permission. You are responsible for your use and apply or restore this tweak at your own risk.",
            version: version,
            author: "zeroxjf, kolbicz, ezzuldinSt",
            category: "Beta",
            symbolName: "location.fill",
            kind: .DirectTool,
            enabledKey: nil,
            isNew: true)
        locationSim.settingsSection = 20 // SectionLocationSim
        locationSim.experimental = false
        locationSim.unstableWarning = "Beta: requires Apple Maps installed and set up. Changes CoreLocation's active simulation state — may affect time zone, date/time, and other location-tied behavior. Some apps and services prohibit or detect simulated locations. Only use this if you know what you're doing."

        let snowboardLite = Package(
            identifier: "com.darksword.snowboardlite",
            name: "SnowBoard Lite",
            shortDescription: "Local SnowBoard-style icon themes",
            longDescription: "Imports SnowBoard/IconBundles themes into a local library and applies the selected theme through Cyanide's icon replacement pipeline. Supports the bundled iOS 6 theme and local folder imports.\n\nSnowBoard Lite is the main icon-theme entry point in Cyanide.\n\nPorted from d1y/cyanide-ios.",
            version: version,
            author: "d1y",
            category: "Beta",
            symbolName: "square.stack.3d.up.fill",
            kind: .Toggle,
            enabledKey: kSettingsSnowBoardLiteEnabled,
            isNew: true)
        snowboardLite.settingsSection = 18 // SectionSnowBoardLite
        snowboardLite.unstableWarning = "Preview: import or select a SnowBoard Lite theme before applying."

        let liveWP = Package(
            identifier: "com.darksword.livewp",
            name: "LiveWP",
            shortDescription: "Video wallpaper for Home and Lock Screen",
            longDescription: "Plays a selected MP4/MOV/M4V video behind SpringBoard's home and lock screen windows while Cyanide keeps the RemoteCall session alive.\n\nPorted from d1y/cyanide-ios.",
            version: version,
            author: "d1y",
            category: "Beta",
            symbolName: "play.rectangle.fill",
            kind: .Toggle,
            enabledKey: kSettingsLiveWPEnabled,
            isNew: true)
        liveWP.settingsSection = 19 // SectionLiveWP

        let layoutExtras = Package(
            identifier: "com.darksword.layoutextras",
            name: "Home Layout Extras",
            shortDescription: "Extra home/dock padding and per-icon scaling",
            longDescription: "Adds extra padding around the home grid and the dock, and scales icons up or down. Stacks on top of SBCustomizer.\n\nDial in left/right/top/bottom padding for the home screen, horizontal padding for the dock, and home/dock icon scale in the Settings tab. Defaults match stock (zero padding, 100% scale).\n\nApplied at Run; not persisted across respring.\n\niOS 18: mutates the SBIconController layout configuration directly (upstream kolbicz path).\niOS 26: walks the live SBIconListView/SBIconView hierarchy and adjusts frames + iconImageInfo per icon (the iOS 26 layout class is read-only). One-shot at Run on iOS 26 — rotation/page swipe may force iOS 26's auto-layout to re-fit, so re-Run if that happens.",
            version: version,
            author: "kolbicz",
            category: "Home Screen Layout",
            symbolName: "square.dashed.inset.filled",
            kind: .Toggle,
            enabledKey: kSettingsLayoutExtrasEnabled,
            isNew: true)
        layoutExtras.settingsSection = 15 // SectionLayoutExtras
        let iosMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if iosMajor >= 26 {
            layoutExtras.knownIssues = [
                "iOS 26: layout may reset after rotation or page swipe. Re-run to reapply.",
            ]
        }

        let gravityLite = Package(
            identifier: "com.darksword.gravitylite",
            name: "Gravity Lite",
            shortDescription: "Make home-screen icons fall with physics",
            longDescription: "Core RemoteCall-only port of Julio Verne's classic Gravity tweak for iOS 26. Applies UIDynamicAnimator gravity, collision bounds, bounce, friction, resistance, optional dock physics, accelerometer steering, shake pulses, restore, and an explosion pulse to the currently visible SpringBoard icon views.\n\nThis is not a full Substrate-style port. Activator/Home-button hooks, drag gestures, and preference-daemon notifications are intentionally left out. Use Settings to tune the core physics and the Restore button to reset the layout.",
            version: version,
            author: "Julio Verne / zeroxjf",
            category: "Beta",
            symbolName: "arrow.down.circle.fill",
            kind: .Toggle,
            enabledKey: kSettingsGravityLiteEnabled,
            isNew: true)
        gravityLite.settingsSection = 21 // SectionGravityLite
        gravityLite.unstableWarning = "Beta: RemoteCall-only physics can be reset by SpringBoard relayouts such as page swipes, rotations, folder transitions, or resprings. Use Restore Icon Layout if icons stay displaced."
        gravityLite.knownIssues = [
            "To disable, use the App Switcher to return to Cyanide and deactivate Gravity Lite. There is no other way to stop it right now.",
            "Touch input does not register on displaced icons yet. Forwarding taps in this environment is a major WIP.",
            "Install is slow as hell. WIP. Cyanide has to capture every visible icon and widget before physics start.",
            "Page swipes, folder opens, or SpringBoard relayouts may stop the effect. Run Gravity again.",
        ]

        let appSwitcherGrid = Package(
            identifier: "com.darksword.appswitchergrid",
            name: "App Switcher Grid",
            shortDescription: "Grid-style app switcher",
            longDescription: "Applies a runtime SpringBoard method patch that makes the app switcher use grid/deck style.\n\nThis does not write system files. A respring restores the stock app switcher. If you respring after Hide Home Bar, run App Switcher Grid again because respring resets this live SpringBoard patch.\n\nPorted from d1y/cyanide-ios.",
            version: version,
            author: "rooootdev",
            category: "Beta",
            symbolName: "square.grid.2x2.fill",
            kind: .Toggle,
            enabledKey: kSettingsAppSwitcherGridEnabled,
            isNew: true)
        appSwitcherGrid.settingsSection = 22 // SectionAppSwitcherGrid
        appSwitcherGrid.unstableWarning = "Beta: patches SpringBoard runtime methods in memory. Respring restores stock, but unsupported builds may glitch the app switcher or crash SpringBoard. Re-run after any respring."

        var fastLockXLite: Package? = nil
        if privateAvailable {
            let flx = Package(
                identifier: "com.darksword.fastlockx-lite",
                name: "FastLockX Lite",
                shortDescription: "Face ID retry + unlock controls",
                longDescription: "RemoteCall-only port of the usable FastLockX primitives recovered from the iOS 15 tweak by Artem Kasper.\n\nCredits: original FastLockX by Artem Kasper; Cyanide FastLockX Lite port by zeroxjf.\n\nIt can pulse SpringBoard's biometric retry path, ask the iOS 26 biometric coordinator to start a Mesa/Face ID unlock, and send the original Lock Screen unlock request as a fallback. The Always On button keeps those retry/unlock requests armed with SpringBoard timers so pickup-to-unlock can work after Cyanide's 15-second test window ends.\n\nUse Disable, Clean Up, or a respring to stop the timers.",
                version: version,
                author: "Artem Kasper / zeroxjf",
                category: "Experimental",
                symbolName: "lock.open.fill",
                kind: .DirectTool,
                enabledKey: nil,
                isNew: true)
            flx.settingsSection = 24 // SectionFastLockXLite
            flx.experimental = true
            flx.unstableWarning = "Experimental: sends private SpringBoard lock-screen and biometric-resource messages. Always On runs repeating SpringBoard timers, so disable it or respring if Face ID feels noisy or unstable."
            fastLockXLite = flx
        }

        let nanoRegistry = Package(
            identifier: "com.darksword.nanoregistry",
            name: "Watch Pairing Override",
            shortDescription: "Pair a newer watch or revive an older one",
            longDescription: "Changes the watchOS pairing range saved on this iPhone.\n\nMost people should use watchOS Range 99/23/10/6 in Settings, then apply the override. These are pairing protocol generations, not Apple Watch model numbers. 99 raises the watchOS pairing ceiling. 23 keeps the generation-23 setup protocol accepted. 10 and 6 leave the legacy chip and multi-watch floors at their normal values.\n\nApple Watch Ultra 3 cannot pair on iOS versions below 26 at this time.\n\nSystem-file warning: this modifies the local NanoRegistry compatibility-index MobileAsset and saves a .cyanide.bak backup beside the original file. Pairing-asset edits can fail, partially apply, require a respring or reboot to settle, or leave pairing state inconsistent. You apply or remove this override at your own risk.\n\nRespring or reboot after installing or removing the override before trying to pair.",
            version: version,
            author: "zeroxjf",
            category: "Beta",
            symbolName: "applewatch.radiowaves.left.and.right",
            kind: .NanoRegistry,
            enabledKey: nil,
            isNew: true)
        nanoRegistry.settingsSection = 16 // SectionNanoRegistry
        nanoRegistry.unstableWarning = "Warning: modifies a local NanoRegistry MobileAsset. Cyanide saves a .cyanide.bak backup beside the original, but system-file edits can fail or require a respring/reboot. Apply or remove this override at your own risk."

        let callRecordingSound = Package(
            identifier: "com.darksword.callrecording-sound",
            name: "Call Recording Sound",
            shortDescription: "Silence disclosure start/stop sounds",
            longDescription: "Replaces the CallServices StartDisclosureWithTone and StopDisclosure audio files with Cyanide's bundled silent payloads.\n\nCredits: YangJiiii (@duongduong0908) for the EnsWilde and Disable Call Recording BookRestore reference tools. @Little_34306 is credited by the original projects for the Disable Call Recording concept. Cyanide port, KRW-backed implementation, and generated replacement silent audio assets by zeroxjf.\n\nSystem-file warning: this modifies files under /var/mobile/Library/CallServices/Greetings/default. Cyanide backs up the first originals into its app container, but system file replacement can fail, partially apply, or require a respring/reboot to settle.\n\nLegal note: call-recording disclosure sounds may exist to satisfy consent, notification, or privacy-law requirements in some places. You are responsible for understanding and following the laws that apply to you.\n\nThis port does not use the old Books/BookRestore/sparserestore path. Cyanide runs KRW, unlocks local /private/var write access, then writes directly to the CallServices files.\n\nUse Restore Original Sounds to write Cyanide's backups back when present. You apply or restore this tweak at your own risk.",
            version: version,
            author: "YangJiiii (@duongduong0908) / zeroxjf",
            category: "Beta",
            symbolName: "speaker.slash.fill",
            kind: .CallRecordingSound,
            enabledKey: nil,
            isNew: true)
        callRecordingSound.experimental = false
        callRecordingSound.unstableWarning = "Beta: persistent CallServices system-file replacement. Disclosure sounds may be legally required where you live; you are responsible for your use and apply this at your own risk. Use Restore Original Sounds before removing Cyanide if you want Cyanide's backups written back."

        let hideHomeBar = Package(
            identifier: "com.darksword.hide-home-bar",
            name: "Hide Home Bar",
            shortDescription: "Hide the bottom home indicator",
            longDescription: "Zeros the first page of /System/Library/PrivateFrameworks/MaterialKit.framework/Assets.car using a DirtyZero-style file-backed page zero, which hides the bottom home indicator after SpringBoard reloads assets.\n\nRun Hide Home Bar by itself, then respring so SpringBoard refreshes the asset cache. To bring the home indicator back, choose Restore Home Bar and respring again. Other live SpringBoard tweaks, such as App Switcher Grid, should be applied in a separate run after the respring.\n\nCredits: C4ndyF1sh/ZeroCalories for the Home Bar target and jailbreakdotparty/dirtyZero for the page-zeroing idea. Cyanide port by zeroxjf.",
            version: version,
            author: "C4ndyF1sh / jailbreakdotparty / zeroxjf",
            category: "Beta",
            symbolName: "line.3.horizontal",
            kind: .HideHomeBar,
            enabledKey: nil,
            isNew: true)
        hideHomeBar.unstableWarning = "Beta: DirtyZero-style system asset page zeroing. Run by itself, then respring after hiding. To restore the home indicator, choose Restore Home Bar and respring."

        let otaBlock = Package(
            identifier: "com.darksword.ota-block",
            name: "OTA Updates",
            shortDescription: "Enable or disable over-the-air system updates",
            longDescription: "Disables or enables the launchd jobs responsible for over-the-air system updates by editing disabled.plist. State persists across reboots.\n\nSystem-file warning: this edits /private/var/db/com.apple.xpc.launchd/disabled.plist. Incorrect or partial writes can affect launchd job state across boot. You disable or re-enable OTA updates at your own risk.\n\nNo Run/Apply step required for this package. Use Disable to block OTA updates, or Enable to restore them.",
            version: version,
            author: "kolbicz",
            category: "System Updates",
            symbolName: "icloud.slash.fill",
            kind: .OTA,
            enabledKey: nil,
            isNew: false)
        otaBlock.unstableWarning = "Warning: persistent system-file edit. This package modifies launchd disabled.plist to change OTA job state across reboot. Disable or re-enable OTA updates at your own risk."

        let disableAppLibrary = Package(
            identifier: "com.darksword.disable-app-library",
            name: "Disable App Library",
            shortDescription: "Remove the App Library page",
            longDescription: "Removes the App Library page that sits past your last home-screen page. Swiping past the last page becomes a no-op.",
            version: version,
            author: "kolbicz",
            category: "SpringBoard Tweaks",
            symbolName: "square.grid.2x2.fill",
            kind: .Toggle,
            enabledKey: kSettingsDSDisableAppLibrary,
            isNew: false)

        let disableIconFlyIn = Package(
            identifier: "com.darksword.disable-icon-flyin",
            name: "Disable Icon Fly-In",
            shortDescription: "Skip the icon spring animation",
            longDescription: "Skips the spring animation that plays when home screen icons appear after unlock or app switch. Icons just appear in their final position.",
            version: version,
            author: "kolbicz",
            category: "SpringBoard Tweaks",
            symbolName: "sparkles",
            kind: .Toggle,
            enabledKey: kSettingsDSDisableIconFlyIn,
            isNew: false)

        let zeroWakeAnimation = Package(
            identifier: "com.darksword.zero-wake-animation",
            name: "Zero Wake Animation",
            shortDescription: "Snap on instantly when waking",
            longDescription: "Removes the fade-in animation when waking the display. The screen pops on at full brightness immediately.",
            version: version,
            author: "kolbicz",
            category: "SpringBoard Tweaks",
            symbolName: "moon.zzz.fill",
            kind: .Toggle,
            enabledKey: kSettingsDSZeroWakeAnimation,
            isNew: false)

        let zeroBacklightFade = Package(
            identifier: "com.darksword.zero-backlight-fade",
            name: "Zero Backlight Fade",
            shortDescription: "Instant lock/unlock backlight",
            longDescription: "Cuts the backlight fade duration to zero so the display switches on or off instantly on lock and unlock.",
            version: version,
            author: "kolbicz",
            category: "SpringBoard Tweaks",
            symbolName: "sun.max.fill",
            kind: .Toggle,
            enabledKey: kSettingsDSZeroBacklightFade,
            isNew: false)

        let doubleTapToLock = Package(
            identifier: "com.darksword.double-tap-to-lock",
            name: "Double-Tap to Lock",
            shortDescription: "Lock with a wallpaper double-tap",
            longDescription: "Double-tap an empty area of the wallpaper to lock the device. No more reaching for the side button.",
            version: version,
            author: "kolbicz",
            category: "SpringBoard Tweaks",
            symbolName: "hand.tap.fill",
            kind: .Toggle,
            enabledKey: kSettingsDSDoubleTapToLock,
            isNew: false)

        let drag = Package(
            identifier: "com.darksword.drag-coefficient",
            name: "Drag Coefficient",
            shortDescription: "Custom SpringBoard animation speed multiplier",
            longDescription: "Overrides _UIAnimationDragCoefficient in SpringBoard to make all UIKit spring animations faster or slower.\n\nSet the coefficient in the Drag Coefficient settings panel. 50% = 0.50× (2× faster), 25% = 0.25× (4× faster), 100% = stock.\n\nImported from kolbicz/DarkSword-Tweaks.",
            version: version,
            author: "kolbicz",
            category: "SpringBoard Tweaks",
            symbolName: "dial.medium.fill",
            kind: .Toggle,
            enabledKey: kSettingsDSDragCoefficientEnabled,
            isNew: true)
        drag.settingsSection = 14 // SectionDragCoefficient

        var list: [Package] = [
            statBar,
            nsBar,
            niceBarLite,
            sbc,
            layoutExtras,
            gravityLite,
            powercuff,
            disableAppLibrary,
            disableIconFlyIn,
            zeroWakeAnimation,
            zeroBacklightFade,
            doubleTapToLock,
            drag,
            otaBlock,
        ]

        // Beta last so the warning sits at the bottom of the Installer.
        if let s = signal { list.append(s) }
        list += [axon, nanoRegistry, callRecordingSound, hideHomeBar]
        if let tb = typeBanner { list.append(tb) }
        if let ni = notificationIsland { list.append(ni) }
        if let ipa = ipaDecryptor { list.append(ipa) }
        if let ss = stageStrip { list.append(ss) }
        if let flx = fastLockXLite { list.append(flx) }
        list += [locationSim, snowboardLite, liveWP, appSwitcherGrid]

        return list
    }
}
