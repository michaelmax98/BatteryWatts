# BetterBattery

**A tiny macOS menu bar app that shows — live, every second — how much power is flowing into (or out of) your MacBook's battery.**

<p align="center">
  <a href="https://github.com/michaelmax98/BetterBattery/releases/latest/download/BetterBattery.dmg">
    <img src="docs/download-button.svg" width="232" alt="Download for macOS (DMG)">
  </a>
  <br>
  <sub>Direct download · macOS 13+ · free &amp; open source · <a href="https://github.com/michaelmax98/BetterBattery/releases/latest">all releases</a></sub>
</p>

[![Latest release](https://img.shields.io/github/v/release/michaelmax98/BetterBattery?label=latest&color=2ea44f)](https://github.com/michaelmax98/BetterBattery/releases/latest)
[![CI](https://github.com/michaelmax98/BetterBattery/actions/workflows/ci.yml/badge.svg)](https://github.com/michaelmax98/BetterBattery/actions/workflows/ci.yml)

A clean, flat, iOS-style battery icon sits in your menu bar. Click it for the live panel: charge/discharge wattage, battery percentage ring, time to full or time remaining, charger wattage, battery health, and cycle count.

## Install

1. Click the **Download** button above (it always grabs the newest DMG)
2. Open it and drag **BetterBattery** into **Applications**
3. Launch it from Applications — the battery icon appears in your menu bar

> **First launch on a fresh download:** releases aren't notarized with a paid Apple Developer ID (yet), so macOS may block the first open. If double-clicking shows a warning, go to **System Settings → Privacy & Security**, scroll down to the "BetterBattery was blocked" notice, and click **Open Anyway** (on older macOS versions, right-click the app → **Open** works too). This is only needed once.

Requires macOS 13 Ventura or later. No special permissions — battery data is read from public IOKit properties.

## Features

- **Live battery wattage** — positive and green while charging (energy flowing into the battery), and the real-time draw while on battery. Read from IOKit's instantaneous amperage × voltage at 1 Hz.
- **iOS-style battery icon** — modern and flat, with the reading punched into the battery shape. Choose what it shows inside: **nothing**, **percentage** (like `75`), **time remaining** (like `6h35m`; time to full while charging), or **live watts** with a direction arrow — `▴26W` charging into the battery, `▾8.4W` being drawn from it.
- **State color theme** — green while charging or plugged in, blue on battery, then orange and red as you cross your low-battery thresholds. The panel ring, the wattage number, and the menu bar icon all follow.
- **Low-battery alerts** — configurable warning and critical percentages, plus an optional pulsing neon glow around the screen edges (orange, then red) so a dying battery is impossible to miss. When the charger lands mid-glow, an optional green celebration shimmer fades it out. Test buttons preview every effect — press Esc to end a preview.
- **Time estimates** — time to full / time remaining, same numbers as the system battery menu.
- **History charts** — battery level or charge/discharge wattage over a selectable **4h / 24h / 7d** window, with history persisted to disk across relaunches, an optional **temperature overlay** (one click on the temp chip), and a long-term **Health trend** view built from daily snapshots.
- **Charge limit aware** — pairs with macOS Tahoe 26.4's native 80–95% charge limit: one click opens the Battery setting, and the panel shows when charging is being held.
- **Stats for nerds** — a collapsible grid of live tiles: battery temperature with a gauge, a fan that actually spins at the real RPM, volts × amps, session energy and average draw, adapter wattage, capacity bar (current / full / design mAh), color-coded health and cycles, and lifetime energy — measured since install plus an estimate from your battery's cycle history, translated into how long it could power the average U.S. home.
- **A calm, glanceable layout** — hero readout and history up top; Settings, Low Battery, and Stats for Nerds tucked into collapsible sections; update controls anchored at the bottom.
- **In-app updates** — the app checks this repo's Releases page and can download and open the new version for you.
- Native SwiftUI, light/dark aware, no Dock icon, optional Launch at Login.

## Updates

BetterBattery checks GitHub for a new release every few hours (and there's a **Check for Updates** button in the panel). When one is available, click **Install Update** — the app downloads the new version, verifies it against the sha256 GitHub publishes for the release, swaps itself in place, and relaunches. One click, no dragging.

## Build from source

```bash
git clone https://github.com/michaelmax98/BetterBattery.git
cd BetterBattery
swift run -c release      # run it directly
./build-app.sh            # or build build/BetterBattery.app
```

Releases are built by [GitHub Actions](.github/workflows/release.yml): pushing a `v*` tag compiles the app on a macOS runner, packages the DMG, and publishes it to the Releases page.

## How it reads power

Wattage comes from the `AppleSmartBattery` IORegistry entry (`InstantAmperage` × `Voltage`). Positive means the battery is being charged; negative means it's powering the Mac. Two things that are normal: into-battery watts are lower than your charger's rating (the charger also powers the Mac itself), and ~0 W while plugged in means the battery is full or Optimized Battery Charging is holding it.

## License

[MIT](LICENSE)
