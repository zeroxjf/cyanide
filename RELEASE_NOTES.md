# Release Notes

Keep concrete, user-facing release bullets here as changes land. The release
script reads `## Pending` before building, uses those bullets for GitHub release
notes and the generated in-app changelog, then moves them under `## Released`
after a successful build.

Good bullets describe the behavior users will notice:

- Reduced flicker when Dynamic Stage windows resize.
- Fixed installer queue badges after changing package selection.
- Added an iOS 17 fallback for Disable App Library.

Avoid vague bullets like "Update settings", "Change project files", or
"Misc fixes".

## Pending


## Released

### v1.2.5 - 2026-06-05

- [x] Replaced the first-launch log collection notice with a Cyanide Signal group invite for feedback, feature requests, and support.
- [x] Added NSBar, NiceBar Lite, SnowBoard Lite, and LiveWP ports from d1y/cyanide-ios, with Settings controls and Installer package credits.
- [x] Allowed public Cyanide checkouts to build without the private experimental tweak submodule.

### v1.2.4 - 2026-06-03

- [x] Added a StatBar refresh-rate setting and reduced battery use from repeated temperature polling.
- [x] Fixed Installer queue edge cases so no-op applies finish cleanly and pending activations are remembered after reopening Cyanide.

### v1.2.3 - 2026-06-03

- [x] Improved Gravity Lite startup on iOS 17 by using the faster live-icon capture path.
- [x] Fixed a recent tweak startup regression that could hang while opening the SpringBoard injection channel on A16+ iPhones.
- [x] Fixed Installer package state so successfully applied SpringBoard tweaks no longer appear stuck as activation pending.

### v1.2.2 - 2026-06-03

- [x] Fixed kernel panic on A16+/M-series iPads by guarding the t1sz_boot override so the PAC mask uses the correct value.

### v1.2.1 - 2026-06-03

- [x] Added Drag Coefficient tweak — custom SpringBoard animation speed multiplier ported from kolbicz/DarkSword-Tweaks, with a 5–200% slider (50% = 2× faster, 100% = stock).

### v1.2.0 - 2026-06-03

- [x] Added Gravity Lite with home screen and dock icon physics, tilt control, widget support, and iOS 18/26 compatibility.
- [x] Polished installer, settings, and log presentation with clearer status text, cleaner startup branding, and a maintained release-notes workflow.
- [x] Improved tweak activation and cleanup so unchanged tweaks are not reapplied unnecessarily and SpringBoard-backed tweaks deactivate more reliably.

### v1.1.22 - 2026-06-02

- [x] Reduced flicker when Dynamic Stage windows resize by staging new scene hosts and retiring old hosts after the remote layer has populated.
- [x] Added stronger transition shielding around Dynamic Stage app open, close, and apply paths.
- [x] Tracked DarkSword toggle apply results independently in Settings.
- [x] Improved Disable App Library handling with an iOS 17 fallback path.
- [x] Refined installer queue, badges, and activity status UI.
- [x] Tightened Log tab typography for dense verbose traces.
- [x] Updated the release script to capture dirty submodule changes before committing and tagging the parent release.
