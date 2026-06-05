<p align="center">
  <img src="https://raw.githubusercontent.com/zeroxjf/cyanide/main/Cyanide/Assets.xcassets/AppIcon.appiconset/icon-ios-1024x1024.png" alt="Cyanide" width="160">
</p>

<h1 align="center">Cyanide</h1>

**By [@zeroxjf](https://github.com/zeroxjf)** — an iOS tweak runner built on top of the DarkSword kernel r/w primitive.

Cyanide is a fork of [`wh1te4ever/darksword-kexploit-fun`](https://github.com/wh1te4ever/darksword-kexploit-fun)
for iOS kernel research. It wraps the native DarkSword kernel stages in an
Objective-C iOS app, restructures the UI as an Installer/Settings split, and
adds a few reliability fixes for repeated local testing. It does not ship
the browser-delivered WebKit/dyld parts of the original DarkSword chain.

## Install

Open this page on your iPhone/iPad and tap one of the buttons below.

<p align="center">
  <a href="https://celloserenity.github.io/altdirect/?url=https://raw.githubusercontent.com/zeroxjf/cyanide/main/source.json" target="_blank">
    <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/AltSource_Blue.png?raw=true" alt="Add AltSource" width="200">
  </a>
  <a href="https://github.com/zeroxjf/cyanide/releases/latest" target="_blank">
    <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/Download_Blue.png?raw=true" alt="Download .ipa" width="200">
  </a>
</p>

## Patreon

Early access to experimental tweaks (Dynamic Stage Lite, Signal Readouts,
TypeBanner, Location Simulator, Call Recording Sound, and future work) is
available to [Patreon supporters](https://www.patreon.com/zeroxjf) at the
Member tier and above.

## Tweaks

These tweaks have been tested on iOS 18.x and 26.x. Expect version drift in
SpringBoard and related daemons to break things on other releases.

### Status Bar

- **StatBar**: battery temperature and free-RAM overlay anchored to the
  SpringBoard status bar, with optional C/F and network-speed display.
- **NSBar**: compact live download/upload speed overlay for the status bar,
  with selectable corner/center positions. Ported from
  [`d1y/cyanide-ios`](https://github.com/d1y/cyanide-ios).
- **NiceBar Lite**: configurable status-bar-adjacent labels for custom text,
  date/time formats, battery, memory, traffic, uptime, IP address, disk,
  thermal state, and other live readouts. Ported from
  [`d1y/cyanide-ios`](https://github.com/d1y/cyanide-ios).

### Home Screen Layout

- **SBCustomizer**: dock icon count, home-screen columns/rows, and hidden icon
  labels. Native port of the lightsaber sbcustomizer payload.
- **Home Layout Extras**: extra padding around the home grid and dock, plus
  per-icon scale for home and dock icons. Stacks on top of SBCustomizer.

### Performance

- **Powercuff**: CPU/GPU underclocking through simulated `thermalmonitord`
  pressure levels (off, nominal, light, moderate, heavy). Lasts until reboot.
  Port of [`rpetrich/Powercuff`](https://github.com/rpetrich/Powercuff).

### SpringBoard Tweaks

Ported from [`kolbicz/DarkSword-Tweaks`](https://github.com/kolbicz/DarkSword-Tweaks):

- **Disable App Library**: removes the App Library page past the last home screen.
- **Disable Icon Fly-In**: skips the spring-in animation when icons appear.
- **Zero Wake Animation**: snaps the display on instantly when waking.
- **Zero Backlight Fade**: instant lock/unlock backlight.
- **Double-Tap to Lock**: lock the device with a wallpaper double-tap.

### System Updates

- **Disable OTA Updates**: toggles the launchd OTA `disabled.plist` to block or
  unblock update prompts. Persists across reboots.

### Beta

> ⚠︎ Work in progress — these work but may change or need re-applying between builds.

- **Gravity Lite**: core port of Julio Verne's classic Gravity tweak. Applies
  UIDynamicAnimator physics to home-screen and dock icons — gravity, collisions,
  bounce, friction, accelerometer steering, shake pulses, and an explosion
  button. Use Restore Icon Layout if icons stay displaced after deactivating.
- **Axon Lite**: groups Notification Center requests by app with a SpringBoard
  overlay and dedups duplicates while the RemoteCall session is alive.
- **Cyanide Themer**: per-bundle icon theme engine. Walks SpringBoard's
  SBIconView hierarchy and swaps each icon's image with a PNG matched on bundle
  ID. Ships with iOS 6 Theme; also accepts a custom folder of `<bundleID>.png`
  files or a binary plist. Pick a theme in Settings before running.
- **SnowBoard Lite**: imports SnowBoard/IconBundles-style theme folders or
  archives into Cyanide's local theme library, then applies the selected theme
  through the existing icon replacement pipeline. Ported from
  [`d1y/cyanide-ios`](https://github.com/d1y/cyanide-ios).
- **LiveWP**: copies a selected MP4/MOV/M4V into Cyanide's app container and
  plays it behind SpringBoard's home and lock screen windows while the live
  RemoteCall session is active. Ported from
  [`d1y/cyanide-ios`](https://github.com/d1y/cyanide-ios).
- **Watch Pairing Override**: edits the watchOS pairing range stored on the
  iPhone so you can pair a newer Apple Watch or revive an older one. Persists
  across reboots; respring before pairing.

### Experimental

> ⚠︎ Unstable or in-development — require Experimental Tweaks to be enabled in Settings.
>
> Experimental tweaks ship early to [Patreon supporters](https://www.patreon.com/zeroxjf) before public release.

- **Dynamic Stage Lite**: brings Stage Manager-style split-view to iPhone over
  RemoteCall — no jailbreak required. Hosts a second app's scene alongside
  SpringBoard using the same scene-hosting design as [`tomt000`'s Dynamic Stage](https://havoc.app/package/dynamicstage).
- **Signal Readouts**: replaces the signal-strength glyphs with live numeric
  readouts — RSRP dBm on cellular, bar count on WiFi.
- **TypeBanner**: shows a pill banner below the Dynamic Island when the active
  Messages conversation shows a typing indicator. Detection fires only while
  Messages.app is running.
- **Location Simulator**: drives Apple's CoreLocation simulation path from a
  RemoteCall host process and sets a static target coordinate. Simulated
  locations may violate app terms, platform rules, game rules, ride-share or
  delivery policies, or local law depending on how they are used. Use only where
  you have permission; you are responsible for your use and apply or restore it
  at your own risk. It may also affect location-tied system behavior such as
  time zone/date/time handling and can have unintended consequences; only use it
  if you know what you're doing. Credits: `kolbicz` provided the
  RemoteCall/CLSimulationManager GPS spoofer prototype, and `ezzuldinSt`'s
  LSpoof provided the app-side spoofing, picker, bookmarks, and route-simulation
  reference.
- **Call Recording Sound**: replaces the CallServices
  `StartDisclosureWithTone` and `StopDisclosure` audio files with Cyanide's
  bundled silent payloads, with separate Silence and Restore actions. Cyanide
  backs up the first originals into its app container before replacement, but
  this is still a persistent system-file edit under
  `/var/mobile/Library/CallServices/Greetings/default`. Disclosure sounds may be
  legally required where you live; you are responsible for your use and should
  restore the originals before removing Cyanide if you want Cyanide's backups
  written back. Credits: `YangJiiii` (`@duongduong0908`) for the EnsWilde and
  Disable Call Recording BookRestore reference tools, and `@Little_34306` as
  credited by the original projects for the Disable Call Recording concept.

## Supported Targets

Tested target range:

- iOS/iPadOS 17.0 through 18.7.1
- iOS/iPadOS 26.0 through 26.0.1
- A19/M5 devices are not supported

The kernel bugs used here, `CVE-2025-43510` and `CVE-2025-43520`, were fixed in
iOS/iPadOS 18.7.2 and 26.1. Later builds are outside this kernel exploit window.

## What This Fork Changes

- Cleans shared exploit state before each attempt.
- Matches the target process with an explicit marker.
- Validates sockets before using the spray path.
- Treats missed races as retryable failures instead of hard failures.
- Tightens the A18/M4 `pe_v2` path with initialized target-file contents,
  stable local remap addresses, bounded page freeing, socket-spray preflight
  checks, and controlled zone-trim retries.

## Kernel Research Features

- Escape the app sandbox.
- Control or crash userspace processes from the app.
- Change UID, GID, and sticky bits on target files.
- Disable ASLR by setting `P_DISABLE_ASLR` in `launchd`'s `proc->p_flag`.

## Credits

- [`opa334`](https://github.com/opa334): original [`darksword-kexploit`](https://github.com/opa334/darksword-kexploit), ChOma, and XPF — the kernel r/w primitive Cyanide is built on.
- [`wh1te4ever`](https://github.com/wh1te4ever): [`kfun` / `darksword-kexploit-fun`](https://github.com/wh1te4ever/darksword-kexploit-fun) — the RemoteCall implementation that lets a sideloaded app apply tweaks inside SpringBoard. Cyanide is a fork of this project.
- [`rooootdev`](https://github.com/rooootdev): working kexploit behavior used to stabilize this fork.
- [`neonmodder123`](https://github.com/neonmodder123): Web Respring method.
- [`kolbicz`](https://github.com/kolbicz): OTA Disabler, SpringBoard tweaks, and
  the RemoteCall/CLSimulationManager GPS spoofer prototype used as the starting
  point for Location Simulator.
- `ezzuldinSt`: LSpoof app-side `CLLocationManager` spoofing, picker,
  bookmarks, and route-simulation reference used while shaping Location
  Simulator.
- `YangJiiii` (`@duongduong0908`): EnsWilde and Disable Call Recording
  BookRestore reference tools used while shaping Call Recording Sound.
- `@Little_34306`: credited by the original call-recording projects for the
  Disable Call Recording concept.
- [`rpetrich`](https://github.com/rpetrich): Powercuff.
- [Julio Verne](https://github.com/julioverne): the original [Gravity](https://github.com/julioverne/Gravity) tweak that Gravity Lite is a core port of.
- [`d1y`](https://github.com/d1y): [`cyanide-ios`](https://github.com/d1y/cyanide-ios)
  AGPL-3.0 sources used for the NSBar, NiceBar Lite, SnowBoard Lite, and
  LiveWP ports.
- [`tomt000`](https://github.com/tomt000): [Dynamic Stage](https://havoc.app/package/dynamicstage) — the original Stage Manager-for-iPhone tweak whose split-view + scene-hosting design Dynamic Stage Lite re-implements over RemoteCall.

### UI inspiration

- The classic [Installer.app](https://github.com/AppTapp/Installer-3) (Ripdev & Nullriver Software, now maintained by AppTapp and the Legacy Jailbreak community) — the iPhoneOS 1 package-manager look that the Cyanide Installer tab is modeled after.
- The [Sileo Project](https://github.com/Sileo/Sileo) (the Sileo Team) — the queue → review → confirm install flow and the bottom queue-popup pattern.

## Build

```sh
./scripts/build.sh
```

The build script uses the `Cyanide` scheme, disables code signing, and writes
an unsigned IPA to:

```text
build/Cyanide.ipa
```

Equivalent manual build:

```sh
xcodebuild \
  -project Cyanide.xcodeproj \
  -scheme Cyanide \
  -sdk iphoneos \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## License

The open-source portion of this repository — everything outside the
`Cyanide/tweaks/private/` submodule — is licensed under **AGPL-3.0**.
See `LICENSE`.

The NSBar, NiceBar Lite, SnowBoard Lite, and LiveWP ports adapt AGPL-3.0 code
from [`d1y/cyanide-ios`](https://github.com/d1y/cyanide-ios) and remain in the
AGPL-covered public tree.

The `Cyanide/tweaks/private/` submodule points at a separate private
repository containing the closed-source experimental tweak
implementations. Those files are
**All Rights Reserved**, distributed in compiled form only inside
official Cyanide releases, and gated to active Patreon supporters at the
Member tier or above. Public clones won't be able to fetch the
submodule, and the experimental tweaks will be absent from local builds
unless you re-implement them. The public app target still builds without
that submodule.
