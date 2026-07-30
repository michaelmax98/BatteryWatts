# BatteryWatts

**A tiny macOS menu bar app that shows — live, every second — how much power is flowing into (or out of) your MacBook's battery.**

[![Latest release](https://img.shields.io/github/v/release/michaelmax98/BatteryWatts?label=download&color=2ea44f)](https://github.com/michaelmax98/BatteryWatts/releases/latest)
[![CI](https://github.com/michaelmax98/BatteryWatts/actions/workflows/ci.yml/badge.svg)](https://github.com/michaelmax98/BatteryWatts/actions/workflows/ci.yml)

![BatteryWatts in the menu bar](docs/menubar-preview.svg)

A retro iPod-style battery icon sits in your menu bar. Click it for the live panel: charge/discharge wattage, battery percentage ring, time to full or time remaining, charger wattage, battery health, and cycle count.

## Install

1. **[Download the latest DMG](https://github.com/michaelmax98/BatteryWatts/releases/latest)**
2. Open it and drag **BatteryWatts** into **Applications**
3. Launch it from Applications — the battery icon appears in your menu bar

> **First launch on a fresh download:** releases aren't notarized with a paid Apple Developer ID (yet), so macOS may block the first open. If double-clicking shows a warning, go to **System Settings → Privacy & Security**, scroll down to the "BatteryWatts was blocked" notice, and click **Open Anyway** (on older macOS versions, right-click the app → **Open** works too). This is only needed once.

Requires macOS 13 Ventura or later. No special permissions — battery data is read from public IOKit properties.

## Features

- **Live battery wattage** — positive and green while charging (energy flowing into the battery), and the real-time draw while on battery. Read from IOKit's instantaneous amperage × voltage at 1 Hz.
- **Retro battery icon** — old-school iOS/iPod style with a solid green fill (red when low). Choose what it displays inside: **nothing**, **percentage**, or **predicted time left** (time to full while charging).
- **Time estimates** — time to full / time remaining, same numbers as the system battery menu.
- **Details panel** — charger wattage, volts × amps, battery health, cycle count.
- **In-app updates** — the app checks this repo's Releases page and can download and open the new version for you.
- Native SwiftUI, light/dark aware, no Dock icon, optional Launch at Login.

## Updates

BatteryWatts checks GitHub for a new release every few hours (and there's a **Check for Updates** button in the panel). When one is available, click **Install Update** — the new DMG downloads and opens; drag to Applications to finish.

## Build from source

```bash
git clone https://github.com/michaelmax98/BatteryWatts.git
cd BatteryWatts
swift run -c release      # run it directly
./build-app.sh            # or build build/BatteryWatts.app
```

Releases are built by [GitHub Actions](.github/workflows/release.yml): pushing a `v*` tag compiles the app on a macOS runner, packages the DMG, and publishes it to the Releases page.

## How it reads power

Wattage comes from the `AppleSmartBattery` IORegistry entry (`InstantAmperage` × `Voltage`). Positive means the battery is being charged; negative means it's powering the Mac. Two things that are normal: into-battery watts are lower than your charger's rating (the charger also powers the Mac itself), and ~0 W while plugged in means the battery is full or Optimized Battery Charging is holding it.

## License

[MIT](LICENSE)
