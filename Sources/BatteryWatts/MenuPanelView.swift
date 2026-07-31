import SwiftUI
import AppKit
import ServiceManagement

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
    @State private var launchAtLogin = false

    // SMAppService needs a real bundle; hide the toggle under `swift run`.
    private var canManageLoginItem: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetContent(monitor: monitor)

            historySection

            Divider()

            VStack(alignment: .leading, spacing: 10) {
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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Low battery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                thresholdRow(label: "Warn", color: PowerAccent.orange, value: $warnThreshold, range: 15...50)
                thresholdRow(label: "Critical", color: PowerAccent.red, value: $criticalThreshold, range: 5...45)
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
            .onChange(of: warnThreshold) { newValue in
                if criticalThreshold >= newValue { criticalThreshold = max(5, newValue - 5) }
            }
            .onChange(of: criticalThreshold) { newValue in
                if newValue >= warnThreshold { warnThreshold = min(50, newValue + 5) }
            }

            updateSection

            Divider()

            nerdSection

            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 324)
        .onAppear {
            if canManageLoginItem {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        HistoryChart(monitor: monitor, modeRaw: $historyModeRaw)
    }

    @ViewBuilder
    private var updateSection: some View {
        if let available = updater.availableVersion {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Version \(available) available", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                    Button(updater.isInstalling ? "Installing…" : "Install Update") {
                        updater.installUpdate()
                    }
                    .controlSize(.small)
                    .disabled(updater.isInstalling)
                }
                if let status = updater.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let current = updater.currentVersion {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(updater.isChecking ? "Checking…" : "Check for Updates") {
                        updater.check(userInitiated: true)
                    }
                    .controlSize(.small)
                    .disabled(updater.isChecking)
                    Spacer()
                    Text("v\(current)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private var nerdSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showNerdStats.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showNerdStats ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Stats for nerds")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showNerdStats && monitor.snapshot.state != .noBattery {
                VStack(alignment: .leading, spacing: 3) {
                    if let temperature = monitor.snapshot.temperatureC {
                        nerdRow("Temperature", String(format: "%.1f °C", temperature))
                    }
                    if let fansText {
                        nerdRow("Fans", fansText)
                    }
                    nerdRow("Electrical", electricalLine)
                    if let capacityText {
                        nerdRow("Capacity", capacityText)
                    }
                    if let healthLine {
                        nerdRow("Health", healthLine)
                    }
                    nerdRow("Lifetime energy", lifetimeText)
                }
                .font(.caption2.monospacedDigit())
            }
        }
    }

    private func nerdRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var fansText: String? {
        guard let fans = monitor.fans else { return nil }
        if fans.isEmpty { return "None (fanless)" }
        if fans.allSatisfy({ $0.rpm < 50 }) { return "Off" }
        return fans.map { String(format: "%.0f rpm", $0.rpm) }.joined(separator: " · ")
    }

    private var capacityText: String? {
        let snap = monitor.snapshot
        guard let full = snap.rawFullmAh else { return nil }
        var text: String
        if let current = snap.rawCurrentmAh {
            text = "\(current) / \(full) mAh"
        } else {
            text = "\(full) mAh full"
        }
        if let design = snap.designmAh {
            text += " · design \(design)"
        }
        return text
    }

    private var lifetimeText: String {
        String(format: "%.1f Wh out · %.1f Wh in", monitor.lifetimeDischargeWh, monitor.lifetimeChargeWh)
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

    private func thresholdRow(label: String, color: Color, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(label) at \(value.wrappedValue)%")
                .font(.caption)
            Spacer()
            Stepper("", value: value, in: range, step: 5)
                .labelsHidden()
                .controlSize(.mini)
        }
    }

    private var electricalLine: String {
        let snap = monitor.snapshot
        return String(format: "%.2f V · %.2f A", snap.voltage, snap.amperage)
    }

    private var healthLine: String? {
        let snap = monitor.snapshot
        switch (snap.healthPercent, snap.cycleCount) {
        case let (health?, cycles?): return "\(health)% · \(cycles) cycles"
        case let (health?, nil): return "\(health)%"
        case let (nil, cycles?): return "\(cycles) cycles"
        default: return nil
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
