# BetterBattery — development notes

macOS menu bar battery app (SwiftUI, macOS 13+, SwiftPM). Formerly named
BatteryWatts.

## Conventions that must hold

- **Panel layout order**: hero readout → history charts → collapsible chip
  sections (Settings / Low Battery / Stats for Nerds, all using the
  `SectionHeader` component) → update controls + Quit anchored at the bottom.

- **Update controls stay at the very bottom of the panel** (just above Quit) —
  explicit user preference; do not move them in layout changes.
- **Efficiency is a feature** (explicit user requirement): the menu bar glyph
  re-renders only when its `cacheKey` changes, and the 1 Hz sampling pauses
  while displays sleep (with a state flush on pause). Don't add timers, disk
  writes, or per-tick allocations casually.

- **Never animate with `TimelineView`.** Its schedule needs SwiftUI to
  re-evaluate the view every frame, and it does **not** tick inside a
  `MenuBarExtra(.window)` panel. The view then only redraws when the model
  publishes — once a second — so anything time-based lurches a whole second
  forward at a time instead of moving. This is exactly how the fan icon
  shipped broken: a 30 fps spin in code, a once-a-second tick on screen.
  Use a render-server animation instead (a `repeatForever` rotation, or
  `.animation(value:)`): handed to the compositor once, no per-frame SwiftUI
  work, and no new timer.

- **Live values must ease, not snap.** This is what separates "smooth" from
  "laggy" across this app family. The models publish at 1 Hz, so any readout
  bound straight to a sample teleports between discrete states. Give numbers
  `.contentTransition(.numericText())`, and give bars/rings/arcs an
  `.animation(.easeOut(…), value:)`. Key the animation on a **quantised**
  value (`Int(fraction * 1000)`, a rounded period) so ordinary sample jitter
  doesn't restart it, and reuse one quantisation across a panel so everything
  moves together instead of at competing rhythms.

- **Panel-only animation is free at idle.** Everything inside the panel is
  unrendered while the menu bar item is closed, so easing and spinners cost
  nothing until someone opens it. That is the *only* reason they're allowed:
  never move a continuous animation into the glyph/menu bar path, and never
  reach for a repeating `Timer` to drive one.

- **Keep per-tick work out of view bodies.** A body inside the panel
  re-evaluates on every 1 Hz publish; anything expensive there runs once a
  second for as long as the panel is open. Derive it in the model, or reduce
  it (NetPulse's chart window is found by bisection, not by filtering all
  17,280 retained samples).
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
