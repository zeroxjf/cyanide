//
//  PackageCatalog.m
//  Cyanide
//

#import "PackageCatalog.h"
#import "../SettingsViewController.h"
#import "../PatreonAuth.h"
#import "../tweaks/private_compat.h"

@implementation PackageCatalog

// Mirrors of the private SettingsSection enum values in SettingsViewController.m
// (kept in sync — must match the underlying section indices used for the
// detail-mode SettingsViewController push).
static const NSInteger kSecSBC              = 4;
static const NSInteger kSecStatBar          = 5;
static const NSInteger kSecNSBar            = 6;
static const NSInteger kSecNiceBarLite      = 7;
static const NSInteger kSecRSSI             = 8;
static const NSInteger kSecPowercuff        = 11;
static const NSInteger kSecDragCoefficient  = 13;
static const NSInteger kSecLayoutExtras     = 14;
static const NSInteger kSecNanoRegistry     = 15;
static const NSInteger kSecThemer           = 16;
static const NSInteger kSecSnowBoardLite    = 17;
static const NSInteger kSecLiveWP           = 18;
static const NSInteger kSecLocationSim      = 19;
static const NSInteger kSecGravityLite      = 20;

+ (NSArray<Package *> *)allPackages
{
    NSArray<Package *> *full = [self allPackagesIncludingExperimental];
    BOOL creator = cyanide_is_creator();
    BOOL experimentalAccess = cyanide_is_patron() || creator;
    BOOL experimentalOn = [[NSUserDefaults standardUserDefaults]
                            boolForKey:kSettingsExperimentalTweaksEnabled]
                            && experimentalAccess;

    NSMutableArray<Package *> *out = [NSMutableArray arrayWithCapacity:full.count];
    for (Package *p in full) {
        if (p.creatorOnly && !creator) continue;
        if (p.experimental && !experimentalOn) continue;
        [out addObject:p];
    }
    return out;
}

+ (NSArray<Package *> *)allPackagesIncludingExperimental
{
    static NSArray<Package *> *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *version = @"1.0";

        Package *statBar = [[Package alloc] initWithIdentifier:@"com.darksword.statbar"
                                           name:@"StatBar"
                               shortDescription:@"Battery temperature + free RAM overlay"
                                longDescription:@"Installs an overlay window in SpringBoard that shows live battery temperature and free RAM next to the system status bar. Refresh timing is adjustable so you can trade live updates for battery life.\n\nConfigure units, visible metrics, and refresh speed in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Status Bar"
                                     symbolName:@"thermometer.medium"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsStatBarEnabled
                                          isNew:NO];
        statBar.settingsSection = kSecStatBar;

        Package *nsBar = [[Package alloc] initWithIdentifier:@"com.darksword.nsbar"
                                           name:@"NSBar"
                               shortDescription:@"Network speed overlay in the status bar"
                                longDescription:@"Displays real-time download and upload speed in a compact SpringBoard status-bar overlay. Pick its corner or center position in Settings.\n\nPorted from d1y/cyanide-ios."
                                        version:version
                                         author:@"d1y"
                                       category:@"Status Bar"
                                     symbolName:@"network"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsNSBarEnabled
                                          isNew:YES];
        nsBar.settingsSection = kSecNSBar;

        Package *niceBarLite = [[Package alloc] initWithIdentifier:@"com.darksword.nicebarlite"
                                           name:@"NiceBar Lite"
                               shortDescription:@"NiceBar-style status labels"
                                longDescription:@"Adds configurable text labels around the status bar. Slots can show custom text, date/time formats, and system values such as battery, memory, network speed, uptime, IP address, disk space, thermal state, and traffic counters.\n\nPorted from d1y/cyanide-ios."
                                        version:version
                                         author:@"d1y"
                                       category:@"Status Bar"
                                     symbolName:@"textformat.size"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsNiceBarLiteEnabled
                                          isNew:YES];
        niceBarLite.settingsSection = kSecNiceBarLite;

#if CYANIDE_PRIVATE_TWEAKS_AVAILABLE
        Package *signal = [[Package alloc] initWithIdentifier:@"com.darksword.rssidisplay"
                                           name:@"Signal Readouts"
                               shortDescription:@"RSRP dBm on cellular, bar count on WiFi"
                                longDescription:@"Replaces the signal-strength glyphs in the status bar with live numeric readouts: RSRP in dBm for cellular, and the active bar count for WiFi. Updates roughly once per second.\n\nToggle WiFi-only or cellular-only in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"In Development"
                                     symbolName:@"antenna.radiowaves.left.and.right"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsRSSIDisplayEnabled
                                          isNew:NO];
        signal.settingsSection = kSecRSSI;
        signal.experimental = YES;
        signal.creatorOnly = YES;
        signal.unstableWarning = @"⚠️ In development — may not work at all. The live status-bar refresh interferes with other SpringBoard tweaks and can drop readouts entirely.";
#endif

        Package *sbc = [[Package alloc] initWithIdentifier:@"com.darksword.sbcustomizer"
                                           name:@"SBCustomizer"
                               shortDescription:@"Custom dock count and home screen grid"
                                longDescription:@"Customizes the dock icon count and the home screen icon grid (columns and rows). Optionally hides icon labels.\n\nAdjust the per-axis counts and the label-hide switch in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Home Screen Layout"
                                     symbolName:@"square.grid.3x3.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSBCEnabled
                                          isNew:NO];
        sbc.settingsSection = kSecSBC;

        Package *powercuff = [[Package alloc] initWithIdentifier:@"com.darksword.powercuff"
                                           name:@"Powercuff"
                               shortDescription:@"Underclock the CPU/GPU thermal pressure"
                                longDescription:@"Drives thermalmonitord with synthetic thermal pressure to underclock the CPU and GPU. Useful for cooling-sensitive workloads or extending runtime under load. Effects persist until reboot.\n\nNominal is the daily-use default. Light, Moderate, and Heavy intentionally underclock the CPU more, so lag and slower app launches mean it is working as intended. Those levels can be too slow for comfortable day-to-day use, especially on older devices.\n\nPick a level in the Settings tab."
                                        version:version
                                         author:@"rpetrich"
                                       category:@"Performance"
                                     symbolName:@"bolt.slash.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsPowercuffEnabled
                                          isNew:NO];
        powercuff.settingsSection = kSecPowercuff;

        Package *axon = [[Package alloc] initWithIdentifier:@"com.darksword.axonlite"
                                           name:@"Axon Lite"
                               shortDescription:@"Group Notification Center requests by app"
                                longDescription:@"Groups visible Notification Center requests by app in a SpringBoard overlay and filters duplicates while Cyanide keeps the RemoteCall session alive.\n\nNo extra configuration."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"bell.badge.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAxonLiteEnabled
                                          isNew:YES];
        axon.unstableWarning = @"⚠️ Experimental: work-in-progress. Expect SpringBoard crashes, dropped notifications, layout glitches, and breakage between Cyanide builds. Don't rely on it for anything important.";

#if CYANIDE_PRIVATE_TWEAKS_AVAILABLE
        Package *typeBanner = [[Package alloc] initWithIdentifier:@"com.darksword.typebanner"
                                           name:@"TypeBanner"
                               shortDescription:@"iMessage typing banner under the Dynamic Island"
                                longDescription:@"Port of TypeMillennium. Shows a pill banner just below the Dynamic Island whenever the active Messages conversation list shows a typing indicator.\n\nv1 limitation: detection runs against the Messages app's own view hierarchy via RemoteCall, so it only fires while Messages.app is running.\n\nNo extra configuration."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"In Development"
                                     symbolName:@"ellipsis.bubble.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsTypeBannerEnabled
                                          isNew:YES];
        typeBanner.experimental = YES;
        typeBanner.creatorOnly = YES;
        typeBanner.unstableWarning = @"⚠️ In development — extremely unstable. Polls MobileSMS over RemoteCall every ~1.5s and is known to crash SpringBoard. Detection only fires while Messages.app is running.";

        Package *stageStrip = [[Package alloc] initWithIdentifier:@"com.darksword.stagestrip"
                                           name:@"Dynamic Stage Lite"
                               shortDescription:@"Two floating app windows, iPad-style"
                                longDescription:
            @"Run two apps as floating, resizable windows on top of SpringBoard.\n\n"
            @"Based on Dynamic Stage by tomt000 — the original Stage Manager-for-iPhone tweak. Dynamic Stage Lite is an independent, RemoteCall-only re-implementation of the split-view + scene-hosting design; no original tweak code or assets are reused. Go check out tomt000's full version on Havoc.\n\n"
            @"How to use:\n"
            @"• Tap the dot in the bottom-right corner of the screen to open the picker.\n"
            @"• Tap two apps to launch them side-by-side.\n"
            @"• Drag the top bar to move; drag any corner to resize.\n"
            @"• X in the top-left of a window closes it.\n"
            @"• Gear in the picker tray jumps back to Cyanide settings.\n\n"
            @"First Run is slow. The picker has to enumerate every installed app over RemoteCall and build a tile for each one — expect 1-2 minutes on a fresh install. Re-Runs reuse the cache and are fast.\n\n"
            @"Rough edges:\n"
            @"• Touch routing into hosted apps isn't wired — windows are for viewing/switching, not scrolling or typing.\n"
            @"• Auto-close on full-screen launch is not yet hooked up; close manually with the X.\n"
            @"• Gestures may stutter while the App Library is still filling in."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Experimental"
                                     symbolName:@"sidebar.left"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsStageStripEnabled
                                          isNew:YES];
        stageStrip.experimental = YES;
        stageStrip.unstableWarning = @"⚠️ Early development. First Run takes 1-2 minutes because the picker enumerates every installed app and builds a tile per app. Re-Runs are fast. Touch routing into hosted windows isn't wired yet, so scrolling/typing inside a floating window may not work.";

        Package *locationSim = [[Package alloc] initWithIdentifier:@"com.darksword.locationsim"
                                           name:@"Location Simulator"
                               shortDescription:@"CoreLocation static point simulation"
                                longDescription:@"Spoofs the device's GPS location via Apple's CLSimulationManager. Requires Apple Maps installed and set up — Maps is the RemoteCall host process that drives the simulation.\n\nThis is a manual tool, not an installable package. Open Controls, choose a target, then use Simulate Current Target or Restore Real Location. Each run opens the activity log and marks completion when the request returns. Reset may take a few minutes and may require a reboot plus extra wait time.\n\nSettings exposes the current target plus altitude and accuracy. v1 is static-point only; route playback and alternate daemon hosts are next.\n\nNot all apps respect the simulated location. Apps that use their own location validation or additional signals may ignore it.\n\nCredits: kolbicz provided the GPS spoofer RemoteCall/CLSimulationManager prototype this is based on. ezzuldinSt's LSpoof provided the app-side CLLocationManager spoofing, picker, bookmarks, and route-simulation reference.\n\nSystem-behavior warning: simulated locations can affect more than maps. Features tied to location, including time zone, date/time behavior, weather, automation, reminders, and service checks, may behave unexpectedly. Only use this if you know what you're doing.\n\nLegal and service-use note: simulated locations may violate app terms, platform rules, game rules, ride-share or delivery policies, or local law depending on how they are used. Use only where you have permission. You are responsible for your use and apply or restore this tweak at your own risk."
                                        version:version
                                         author:@"zeroxjf, kolbicz, ezzuldinSt"
                                       category:@"Experimental"
                                     symbolName:@"location.fill"
                                           kind:PackageInstallKindDirectTool
                                     enabledKey:nil
                                          isNew:YES];
        locationSim.settingsSection = kSecLocationSim;
        locationSim.experimental = YES;
        locationSim.unstableWarning = @"Requires Apple Maps installed and set up. Changes CoreLocation's active simulation state — may affect time zone, date/time, and other location-tied behavior. Some apps and services prohibit or detect simulated locations. Only use this if you know what you're doing.";
#endif

        Package *themer = [[Package alloc] initWithIdentifier:@"com.darksword.themer"
                                           name:@"Cyanide Themer"
                               shortDescription:@"Per-bundle icon theme engine"
                                longDescription:@"Replaces stock app icons by walking SpringBoard's SBIconView hierarchy and swapping each icon's image with a PNG matched on the app's bundle identifier.\n\nPick a theme in Settings > Cyanide Themer. Cyanide ships with iOS 6 Theme, using icons from zagnut531/iOS-6-Icons: https://github.com/zagnut531/iOS-6-Icons. You can also import a custom folder of <bundleID>.png files or a binary plist mapping bundle IDs to PNG data.\n\nApplied at Run; not persisted across respring. The current build also seeds SpringBoard's icon cache and rounds imported PNGs before upload so icons survive common home-screen relayouts more cleanly."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"paintpalette.fill"
                                          kind:PackageInstallKindToggle
                                     enabledKey:kSettingsThemerEnabled
                                          isNew:YES];
        themer.experimental = NO;
        themer.settingsSection = kSecThemer;
        themer.unstableWarning = @"⚠️ Beta: icon theming works but RemoteCall-backed changes may need re-applying after a respring or SpringBoard restart. Pick a theme in Settings > Cyanide Themer before running.";

        Package *snowboardLite = [[Package alloc] initWithIdentifier:@"com.darksword.snowboardlite"
                                           name:@"SnowBoard Lite"
                               shortDescription:@"Local SnowBoard-style icon themes"
                                longDescription:@"Imports SnowBoard/IconBundles themes into a local library and applies the selected theme through Cyanide's icon replacement pipeline. Supports the bundled iOS 6 theme and local folder imports.\n\nPorted from d1y/cyanide-ios."
                                        version:version
                                         author:@"d1y"
                                       category:@"Beta"
                                     symbolName:@"square.stack.3d.up.fill"
                                          kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSnowBoardLiteEnabled
                                          isNew:YES];
        snowboardLite.settingsSection = kSecSnowBoardLite;
        snowboardLite.unstableWarning = @"Preview: import or select a SnowBoard Lite theme before applying.";

        Package *liveWP = [[Package alloc] initWithIdentifier:@"com.darksword.livewp"
                                           name:@"LiveWP"
                               shortDescription:@"Video wallpaper for Home and Lock Screen"
                                longDescription:@"Plays a selected MP4/MOV/M4V video behind SpringBoard's home and lock screen windows while Cyanide keeps the RemoteCall session alive.\n\nPorted from d1y/cyanide-ios."
                                        version:version
                                         author:@"d1y"
                                       category:@"Beta"
                                     symbolName:@"play.rectangle.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLiveWPEnabled
                                          isNew:YES];
        liveWP.settingsSection = kSecLiveWP;

        Package *layoutExtras = [[Package alloc] initWithIdentifier:@"com.darksword.layoutextras"
                                           name:@"Home Layout Extras"
                               shortDescription:@"Extra home/dock padding and per-icon scaling"
                                longDescription:@"Adds extra padding around the home grid and the dock, and scales icons up or down. Stacks on top of SBCustomizer.\n\nDial in left/right/top/bottom padding for the home screen, horizontal padding for the dock, and home/dock icon scale in the Settings tab. Defaults match stock (zero padding, 100% scale).\n\nApplied at Run; not persisted across respring.\n\niOS 18: mutates the SBIconController layout configuration directly (upstream kolbicz path).\niOS 26: walks the live SBIconListView/SBIconView hierarchy and adjusts frames + iconImageInfo per icon (the iOS 26 layout class is read-only). One-shot at Run on iOS 26 — rotation/page swipe may force iOS 26's auto-layout to re-fit, so re-Run if that happens."
                                        version:version
                                         author:@"kolbicz"
                                      category:@"Home Screen Layout"
                                     symbolName:@"square.dashed.inset.filled"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLayoutExtrasEnabled
                                          isNew:YES];
        layoutExtras.settingsSection = kSecLayoutExtras;
        NSInteger iosMajor = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
        if (iosMajor >= 26) {
            layoutExtras.knownIssues = @[
                @"iOS 26: layout may reset after rotation or page swipe. Re-run to reapply.",
            ];
        }

        Package *gravityLite = [[Package alloc] initWithIdentifier:@"com.darksword.gravitylite"
                                           name:@"Gravity Lite"
                               shortDescription:@"Make home-screen icons fall with physics"
                                longDescription:@"Core RemoteCall-only port of Julio Verne's classic Gravity tweak for iOS 26. Applies UIDynamicAnimator gravity, collision bounds, bounce, friction, resistance, optional dock physics, accelerometer steering, shake pulses, restore, and an explosion pulse to the currently visible SpringBoard icon views.\n\nThis is not a full Substrate-style port. Activator/Home-button hooks, drag gestures, and preference-daemon notifications are intentionally left out. Use Settings to tune the core physics and the Restore button to reset the layout."
                                        version:version
                                         author:@"Julio Verne / zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"arrow.down.circle.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsGravityLiteEnabled
                                          isNew:YES];
        gravityLite.settingsSection = kSecGravityLite;
        gravityLite.unstableWarning = @"Beta: RemoteCall-only physics can be reset by SpringBoard relayouts such as page swipes, rotations, folder transitions, or resprings. Use Restore Icon Layout if icons stay displaced.";
        gravityLite.knownIssues = @[
            @"To disable, use the App Switcher to return to Cyanide and deactivate Gravity Lite. There is no other way to stop it right now.",
            @"Touch input does not register on displaced icons yet. Forwarding taps in this environment is a major WIP.",
            @"Install is slow as hell. WIP. Cyanide has to capture every visible icon and widget before physics start.",
            @"Page swipes, folder opens, or SpringBoard relayouts may stop the effect. Run Gravity again.",
        ];

        Package *nanoRegistry = [[Package alloc] initWithIdentifier:@"com.darksword.nanoregistry"
                                           name:@"Watch Pairing Override"
                               shortDescription:@"Pair a newer watch or revive an older one"
                                longDescription:@"Changes the watchOS pairing range saved on this iPhone.\n\nMost people should use watchOS Range 99/23/10/6 in Settings, then apply the override. These are pairing protocol generations, not Apple Watch model numbers. 99 raises the watchOS pairing ceiling. 23 keeps the generation-23 setup protocol accepted. 10 and 6 leave the legacy chip and multi-watch floors at their normal values.\n\nApple Watch Ultra 3 cannot pair on iOS versions below 26 at this time.\n\nSystem-file warning: this modifies the local NanoRegistry compatibility-index MobileAsset and saves a .cyanide.bak backup beside the original file. Pairing-asset edits can fail, partially apply, require a respring or reboot to settle, or leave pairing state inconsistent. You apply or remove this override at your own risk.\n\nRespring or reboot after installing or removing the override before trying to pair."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"applewatch.radiowaves.left.and.right"
                                           kind:PackageInstallKindNanoRegistry
                                     enabledKey:nil
                                          isNew:YES];
        nanoRegistry.settingsSection = kSecNanoRegistry;
        nanoRegistry.unstableWarning = @"Warning: modifies a local NanoRegistry MobileAsset. Cyanide saves a .cyanide.bak backup beside the original, but system-file edits can fail or require a respring/reboot. Apply or remove this override at your own risk.";

#if CYANIDE_PRIVATE_TWEAKS_AVAILABLE
        Package *callRecordingSound = [[Package alloc] initWithIdentifier:@"com.darksword.callrecording-sound"
                                           name:@"Call Recording Sound"
                               shortDescription:@"Silence disclosure start/stop sounds"
                                longDescription:@"Replaces the CallServices StartDisclosureWithTone and StopDisclosure audio files with Cyanide's bundled silent payloads.\n\nCredits: YangJiiii (@duongduong0908) for the EnsWilde and Disable Call Recording BookRestore reference tools. @Little_34306 is credited by the original projects for the Disable Call Recording concept. Cyanide port, KRW-backed implementation, and generated replacement silent audio assets by zeroxjf.\n\nSystem-file warning: this modifies files under /var/mobile/Library/CallServices/Greetings/default. Cyanide backs up the first originals into its app container, but system file replacement can fail, partially apply, or require a respring/reboot to settle.\n\nLegal note: call-recording disclosure sounds may exist to satisfy consent, notification, or privacy-law requirements in some places. You are responsible for understanding and following the laws that apply to you.\n\nThis port does not use the old Books/BookRestore/sparserestore path. Cyanide runs KRW, unlocks local /private/var write access, then writes directly to the CallServices files.\n\nUse Restore Original Sounds to write Cyanide's backups back when present. You apply or restore this tweak at your own risk."
                                        version:version
                                         author:@"YangJiiii (@duongduong0908) / zeroxjf"
                                       category:@"Experimental"
                                     symbolName:@"speaker.slash.fill"
                                           kind:PackageInstallKindCallRecordingSound
                                     enabledKey:nil
                                          isNew:YES];
        callRecordingSound.experimental = YES;
        callRecordingSound.unstableWarning = @"⚠️ Experimental private tweak: persistent CallServices system-file replacement. Disclosure sounds may be legally required where you live; you are responsible for your use and apply this at your own risk. Use Restore Original Sounds before removing Cyanide if you want Cyanide's backups written back.";
#endif

        Package *otaBlock = [[Package alloc] initWithIdentifier:@"com.darksword.ota-block"
                                           name:@"OTA Updates"
                               shortDescription:@"Enable or disable over-the-air system updates"
                                longDescription:@"Disables or enables the launchd jobs responsible for over-the-air system updates by editing disabled.plist. State persists across reboots.\n\nSystem-file warning: this edits /private/var/db/com.apple.xpc.launchd/disabled.plist. Incorrect or partial writes can affect launchd job state across boot. You disable or re-enable OTA updates at your own risk.\n\nNo Run/Apply step required for this package. Use Disable to block OTA updates, or Enable to restore them."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"System Updates"
                                     symbolName:@"icloud.slash.fill"
                                          kind:PackageInstallKindOTA
                                    enabledKey:nil
                                         isNew:NO];
        otaBlock.unstableWarning = @"Warning: persistent system-file edit. This package modifies launchd disabled.plist to change OTA job state across reboot. Disable or re-enable OTA updates at your own risk.";

        Package *disableAppLibrary = [[Package alloc] initWithIdentifier:@"com.darksword.disable-app-library"
                                           name:@"Disable App Library"
                               shortDescription:@"Remove the App Library page"
                                longDescription:@"Removes the App Library page that sits past your last home-screen page. Swiping past the last page becomes a no-op."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"square.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableAppLibrary
                                          isNew:NO];

        list = @[
            statBar,
            nsBar,
            niceBarLite,
            sbc,
            layoutExtras,
            gravityLite,
            powercuff,

            disableAppLibrary,

            [[Package alloc] initWithIdentifier:@"com.darksword.disable-icon-flyin"
                                           name:@"Disable Icon Fly-In"
                               shortDescription:@"Skip the icon spring animation"
                                longDescription:@"Skips the spring animation that plays when home screen icons appear after unlock or app switch. Icons just appear in their final position."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"sparkles"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableIconFlyIn
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.zero-wake-animation"
                                           name:@"Zero Wake Animation"
                               shortDescription:@"Snap on instantly when waking"
                                longDescription:@"Removes the fade-in animation when waking the display. The screen pops on at full brightness immediately."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"moon.zzz.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSZeroWakeAnimation
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.zero-backlight-fade"
                                           name:@"Zero Backlight Fade"
                               shortDescription:@"Instant lock/unlock backlight"
                                longDescription:@"Cuts the backlight fade duration to zero so the display switches on or off instantly on lock and unlock."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"sun.max.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSZeroBacklightFade
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.double-tap-to-lock"
                                           name:@"Double-Tap to Lock"
                               shortDescription:@"Lock with a wallpaper double-tap"
                                longDescription:@"Double-tap an empty area of the wallpaper to lock the device. No more reaching for the side button."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"hand.tap.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDoubleTapToLock
                                          isNew:NO],

            ({
                Package *drag = [[Package alloc] initWithIdentifier:@"com.darksword.drag-coefficient"
                                                               name:@"Drag Coefficient"
                                                   shortDescription:@"Custom SpringBoard animation speed multiplier"
                                                    longDescription:@"Overrides _UIAnimationDragCoefficient in SpringBoard to make all UIKit spring animations faster or slower.\n\nSet the coefficient in the Drag Coefficient settings panel. 50% = 0.50× (2× faster), 25% = 0.25× (4× faster), 100% = stock.\n\nImported from kolbicz/DarkSword-Tweaks."
                                                            version:version
                                                             author:@"kolbicz"
                                                           category:@"SpringBoard Tweaks"
                                                         symbolName:@"dial.medium.fill"
                                                               kind:PackageInstallKindToggle
                                                         enabledKey:kSettingsDSDragCoefficientEnabled
                                                              isNew:YES];
                drag.settingsSection = kSecDragCoefficient;
                drag;
            }),

            otaBlock,

#if CYANIDE_PRIVATE_TWEAKS_AVAILABLE
            callRecordingSound,
#endif

            // Beta last so the warning sits at the bottom of the Installer.
#if CYANIDE_PRIVATE_TWEAKS_AVAILABLE
            signal,
#endif
            axon,
            nanoRegistry,
#if CYANIDE_PRIVATE_TWEAKS_AVAILABLE
            typeBanner,
            stageStrip,
            locationSim,
#endif
            themer,
            snowboardLite,
            liveWP,
        ];
    });
    return list;
}

+ (NSArray<NSString *> *)categoriesInOrder
{
    NSArray<NSString *> *preferred = @[
        @"In Development",
        @"Experimental",
        @"Beta",
        @"Status Bar",
        @"Home Screen Layout",
        @"Other Tweaks",
        @"Performance",
        @"System Updates",
        @"System",
        @"SpringBoard Tweaks",
    ];
    NSMutableArray<NSString *> *all = [NSMutableArray array];
    for (Package *p in [self allPackages]) {
        if (![all containsObject:p.category]) [all addObject:p.category];
    }
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSString *cat in preferred) {
        if ([all containsObject:cat]) [order addObject:cat];
    }
    for (NSString *cat in all) {
        if (![order containsObject:cat]) [order addObject:cat];
    }
    return order;
}

+ (NSDictionary<NSString *, NSArray<Package *> *> *)packagesByCategory
{
    NSMutableDictionary<NSString *, NSMutableArray<Package *> *> *buckets = [NSMutableDictionary dictionary];
    for (Package *p in [self allPackages]) {
        NSMutableArray<Package *> *bucket = buckets[p.category];
        if (!bucket) {
            bucket = [NSMutableArray array];
            buckets[p.category] = bucket;
        }
        [bucket addObject:p];
    }
    return buckets;
}

@end
