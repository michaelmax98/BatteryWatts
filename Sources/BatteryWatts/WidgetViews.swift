import SwiftUI

// MARK: - Formatting

func formatWatts(_ watts: Double) -> String {
    String(format: "%.1f", abs(watts))
}

func formatMinutes(_ minutes: Int) -> String {
    let hours = minutes / 60
    let mins = minutes % 60
    if hours > 0 {
        return "\(hours)h \(mins)m"
    }
    return "\(mins)m"
}

// MARK: - Widget content, shared by the floating widget and the menu bar panel

struct WidgetContent: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        Group {
            if monitor.snapshot.state == .noBattery {
                Label("No battery detected", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                batteryLayout
            }
        }
    }

    private var batteryLayout: some View {
        let snap = monitor.snapshot
        return HStack(spacing: 16) {
            BatteryRing(percent: snap.percent, state: snap.state)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatWatts(snap.smoothedWatts))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(heroColor(for: snap))
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.3), value: snap.smoothedWatts)
                    Text("W")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(caption(for: snap))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(captionColor(for: snap))

                if timeText(for: snap) != nil || snap.adapterWatts != nil {
                    HStack(spacing: 12) {
                        if let time = timeText(for: snap) {
                            Label(time, systemImage: timeSymbol(for: snap))
                        }
                        if let adapter = snap.adapterWatts {
                            Label("\(adapter)W adapter", systemImage: "powerplug")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func heroColor(for snap: BatterySnapshot) -> Color {
        switch snap.state {
        case .charging:
            return .green
        case .discharging:
            return .primary
        case .charged, .pluggedIdle, .noBattery:
            return .secondary
        }
    }

    private func caption(for snap: BatterySnapshot) -> String {
        switch snap.state {
        case .charging: return "Charging · into battery"
        case .discharging: return "On battery"
        case .charged: return "Fully charged"
        case .pluggedIdle: return "Plugged in · not charging"
        case .noBattery: return ""
        }
    }

    private func captionColor(for snap: BatterySnapshot) -> Color {
        snap.state == .charging ? .green : .secondary
    }

    private func timeText(for snap: BatterySnapshot) -> String? {
        switch snap.state {
        case .charging:
            if let minutes = snap.timeToFullMinutes {
                return "\(formatMinutes(minutes)) to full"
            }
            return "estimating…"
        case .discharging:
            if let minutes = snap.timeToEmptyMinutes {
                return "\(formatMinutes(minutes)) left"
            }
            return "estimating…"
        case .charged, .pluggedIdle, .noBattery:
            return nil
        }
    }

    private func timeSymbol(for snap: BatterySnapshot) -> String {
        snap.state == .charging ? "bolt.badge.clock" : "clock"
    }
}

// MARK: - Battery percentage ring

struct BatteryRing: View {
    let percent: Int
    let state: PowerState

    private var progress: CGFloat {
        max(0.02, min(1, CGFloat(percent) / 100))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: percent)
            VStack(spacing: 1) {
                Text("\(percent)%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if state == .charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(width: 68, height: 68)
    }

    private var ringColor: Color {
        switch state {
        case .charging, .charged:
            return .green
        default:
            if percent <= 10 { return .red }
            if percent <= 20 { return .orange }
            return .primary
        }
    }
}
