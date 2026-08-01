import SwiftUI
import AppKit
import ServiceManagement

/// Collapsible section header chip — the panel's shared design language.
struct SectionHeader: View {
    let icon: String
    let title: String
    let tint: [Color]   // one color = solid, two = gradient
    @Binding var expanded: Bool

    private var colors: [Color] {
        tint.count >= 2 ? tint : [tint.first ?? .gray, tint.first ?? .gray]
    }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .foregroundStyle(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            )
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colors.map { $0.opacity(0.12) },
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct MenuPanelView: View {
    @ObservedObject var monitor: PowerMonitor
    @ObservedObject private var updater = UpdateChecker.shared
    @AppStorage(DefaultsKey.menuBarDisplayMode) private var displayModeRaw = MenuBarDisplayMode.percent.rawValue
    @AppStorage(DefaultsKey.warnThreshold) private var warnThreshold = 20
    @AppStorage(DefaultsKey.criticalThreshold) private var criticalThreshold = 10
    @AppStorage(DefaultsKey.lowBatteryGlow) private var lowBatteryGlow = true
    @AppStorage(DefaultsKey.glowWidth) private var glowWidth = 1.0
    @AppStorage(DefaultsKey.plugInCelebration) private var plugInCelebration = true
    @AppStorage(DefaultsKey.historyMode) private var historyModeRaw = HistoryMode.charge.rawValue
    @AppStorage(DefaultsKey.showNerdStats) private var showNerdStats = false
    @AppStorage(DefaultsKey.showSettingsSection) private var showSettingsSection = false
    @AppStorage(DefaultsKey.showLowBatterySection) private var showLowBatterySection = false
    @State private var launchAtLogin = false

    // SMAppService needs a real bundle; hide the toggle under `swift run`.
    private var canManageLoginItem: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Zone 1 — hero glance
            WidgetContent(monitor: monitor)

            Divider()

            // Zone 2 — history
            HistoryChart(monitor: monitor, modeRaw: $historyModeRaw)

            Divider()

            // Zone 3 — collapsible sections, one chip language
            VStack(alignment: .leading, spacing: 6) {
                settingsSection
                lowBatterySection
                nerdSection
            }

            Divider()

            // Zone 4 — update controls live at the very bottom of the panel
            // (standing user preference; keep them here in layout changes).
            footer
        }
        .padding(14)
        .frame(width: 324)
        .onAppear {
            if canManageLoginItem {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
            // Migrate stored thresholds into the 1–20 band (older versions
            // allowed up to 50 in steps of 5).
            if warnThreshold > 20 { warnThreshold = 20 }
            if warnThreshold < 2 { warnThreshold = 2 }
            if criticalThreshold >= warnThreshold { criticalThreshold = max(1, warnThreshold - 1) }
            if criticalThreshold < 1 { criticalThreshold = 1 }
        }
    }

    // MARK: - Settings

    @ViewBuilder
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "gearshape.fill", title: "Settings", tint: [.gray], expanded: $showSettingsSection)

            if showSettingsSection {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Battery icon shows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Battery icon shows", selection: $displayModeRaw) {
                            ForEach(MenuBarDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if canManageLoginItem {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .onChange(of: launchAtLogin) { enabled in
                                updateLoginItem(enabled)
                            }
                    }

                    Button("Charge limit & Battery Settings…") {
                        openBatterySettings()
                    }
                    .controlSize(.mini)
                }
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - Low battery

    @ViewBuilder
    private var lowBatterySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "battery.25", title: "Low Battery", tint: [PowerAccent.orange], expanded: $showLowBatterySection)

            if showLowBatterySection {
                VStack(alignment: .leading, spacing: 6) {
                    thresholdRow(label: "Warn", color: PowerAccent.orange, value: $warnThreshold, range: 2...20)
                    thresholdRow(label: "Critical", color: PowerAccent.red, value: $criticalThreshold, range: 1...19)
                    Toggle("Glow screen edges when low", isOn: $lowBatteryGlow)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    if lowBatteryGlow {
                        HStack(spacing: 8) {
                            Text("Glow intensity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $glowWidth, in: 0.5...2.0)
                                .controlSize(.mini)
                        }
                    }
                    Toggle("Plug-in celebration", isOn: $plugInCelebration)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    HStack(spacing: 6) {
                        Text("Test")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Warn") { GlowController.shared.test(.warning) }
                        Button("Critical") { GlowController.shared.test(.critical) }
                        Button("Plug-in") { GlowController.shared.test(.plugged) }
                        Spacer()
                        Text("esc ends")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .controlSize(.mini)
                }
                .padding(.leading, 4)
                .onChange(of: warnThreshold) { newValue in
                    if criticalThreshold >= newValue { criticalThreshold = max(1, newValue - 1) }
                }
                .onChange(of: criticalThreshold) { newValue in
                    if newValue >= warnThreshold { warnThreshold = min(20, newValue + 1) }
                }
            }
        }
    }

    // MARK: - Stats for Nerds

    @ViewBuilder
    private var nerdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                icon: "atom",
                title: "Stats for Nerds",
                tint: [PowerAccent.blue, PowerAccent.green],
                expanded: $showNerdStats
            )

            if showNerdStats && monitor.snapshot.state != .noBattery {
                NerdStatsView(monitor: monitor)
            }
        }
    }

    // MARK: - Footer (update controls + Quit, single row)

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let available = updater.availableVersion {
                HStack(spacing: 8) {
                    Label("v\(available) available", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                    Button(updater.isInstalling ? "Installing…" : "Install Update") {
                        updater.installUpdate()
                    }
                    .controlSize(.small)
                    .disabled(updater.isInstalling)
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.small)
                    .keyboardShortcut("q")
                }
            } else {
                HStack(spacing: 8) {
                    if updater.currentVersion != nil {
                        Button(updater.isChecking ? "Checking…" : "Check for Updates") {
                            updater.check(userInitiated: true)
                        }
                        .controlSize(.small)
                        .disabled(updater.isChecking)
                    }
                    if let current = updater.currentVersion {
                        Text("v\(current)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.small)
                    .keyboardShortcut("q")
                }
            }
            if let status = updater.statusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func thresholdRow(label: String, color: Color, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(label) at \(value.wrappedValue)%")
                .font(.caption)
            Spacer()
            Stepper("", value: value, in: range, step: 1)
                .labelsHidden()
                .controlSize(.mini)
        }
    }

    private func openBatterySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.battery"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
