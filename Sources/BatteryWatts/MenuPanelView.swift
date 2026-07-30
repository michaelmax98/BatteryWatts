import SwiftUI
import AppKit
import ServiceManagement

struct MenuPanelView: View {
    @ObservedObject var monitor: PowerMonitor
    @ObservedObject private var updater = UpdateChecker.shared
    @AppStorage(DefaultsKey.menuBarDisplayMode) private var displayModeRaw = MenuBarDisplayMode.percent.rawValue
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
                    Text(status).font(.caption2).foregroundStyle(.secondary)
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
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }
            }
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
