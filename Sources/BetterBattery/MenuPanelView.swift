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
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showNerdStats.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "atom")
                        .font(.system(size: 11, weight: .bold))
                    Text("Stats for Nerds")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showNerdStats ? 0 : -90))
                }
                .foregroundStyle(
                    LinearGradient(
                        colors: [PowerAccent.blue, PowerAccent.green],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.vertical, 6)
                .padding(.horizontal, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [PowerAccent.blue.opacity(0.12), PowerAccent.green.opacity(0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)

            if showNerdStats && monitor.snapshot.state != .noBattery {
                NerdStatsView(monitor: monitor)
            }
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
