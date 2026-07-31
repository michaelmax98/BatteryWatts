# BetterBattery — development notes

macOS menu bar battery app (SwiftUI, macOS 13+, SwiftPM). Formerly named
BatteryWatts.

## Conventions that must hold

- **Update controls stay at the very bottom of the panel** (just above Quit) —
  explicit user preference; do not move them in layout changes.
- **Never change `CFBundleIdentifier`** (`com.batterywatts.app`, the pre-rename
  value): UserDefaults (settings, lifetime energy counters) and the
  Launch-at-login registration are keyed to it.
- The in-place updater must never hardcode the app bundle name — it installs
  whatever `.app` the release DMG contains (rename-proof).
- Releases ship via GitHub Actions `release.yml` **workflow_dispatch** with a
  `version` input (the workflow creates the tag server-side); each release
  uploads both `BetterBattery-<version>.dmg` and a stable-named
  `BetterBattery.dmg` so `releases/latest/download/BetterBattery.dmg` always
  works. CI (`ci.yml`) must be green before dispatching.
- The app source is mirrored into the private repo
  `michaelmax98/ClaudeCode` (branch `claude/macos-battery-widget-gl5ba3`,
  folder `BetterBattery/`) after changes land here.
