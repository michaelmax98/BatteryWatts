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
    @State private var launchAtLogin = false

    // SMAppService needs a real bundle; hide the toggle under `swift run`.
    private var canManageLoginItem: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetContent(monitor: monitor)

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
            }
            .onChange(of: warnThreshold) { newValue in
                if criticalThreshold >= newValue { criticalThreshold = max(5, newValue - 5) }
            }
            .onChange(of: criticalThreshold) { newValue in
                if newValue >= warnThreshold { warnThreshold = min(50, newValue + 5) }
            }

            updateSection

            Divider()

            HStack(alignment: .firstTextBaseline) {
                if monitor.snapshot.state != .noBattery {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(electricalLine)
                        if let healthLine {
                            Text(healthLine)
                        }
                    }
                    .font(.caption.monospacedDigit())
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
        .padding(14)
        .frame(width: 324)
        .onAppear {
            if canManageLoginItem {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
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
        case let (health?, cycles?): return "Battery health \(health)% · \(cycles) cycles"
        case let (health?, nil): return "Battery health \(health)%"
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
