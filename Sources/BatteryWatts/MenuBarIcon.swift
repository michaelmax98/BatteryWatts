import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case nothing
    case percent
    case time

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nothing: return "Nothing"
        case .percent: return "Percentage"
        case .time: return "Time left"
        }
    }
}

/// Old-school iOS / iPod style battery: rounded outline, nub on the right,
/// solid green (red when low) fill — optionally with a number drawn inside.
struct RetroBatteryIcon: View {
    let snapshot: BatterySnapshot
    let mode: MenuBarDisplayMode

    private var showsText: Bool { mode != .nothing && snapshot.state != .noBattery }
    private var bodyWidth: CGFloat { showsText ? 33 : 23 }
    private let bodyHeight: CGFloat = 13

    var body: some View {
        HStack(spacing: 1) {
            ZStack {
                // charge fill
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(fillColor.opacity(showsText ? 0.4 : 1.0))
                        .frame(width: fillWidth)
                    Spacer(minLength: 0)
                }
                .padding(2)

                // case outline
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1)

                if showsText {
                    Text(overlayText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if snapshot.state == .charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                }
            }
            .frame(width: bodyWidth, height: bodyHeight)

            // the nub
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.primary.opacity(0.7))
                .frame(width: 2.5, height: 5)
        }
        .frame(height: 15)
    }

    private var fillWidth: CGFloat {
        guard snapshot.state != .noBattery else { return 0 }
        let inner = bodyWidth - 4
        return max(2, inner * CGFloat(snapshot.percent) / 100)
    }

    private var fillColor: Color {
        switch snapshot.state {
        case .noBattery:
            return .secondary
        case .charging, .charged, .pluggedIdle:
            return .green
        case .discharging:
            return snapshot.percent <= 20 ? .red : .green
        }
    }

    private var overlayText: String {
        switch mode {
        case .percent:
            return "\(snapshot.percent)"
        case .time:
            let minutes = snapshot.state == .charging ? snapshot.timeToFullMinutes : snapshot.timeToEmptyMinutes
            if let minutes {
                return String(format: "%d:%02d", minutes / 60, minutes % 60)
            }
            return "–:–"
        case .nothing:
            return ""
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: PowerMonitor
    @AppStorage(DefaultsKey.menuBarDisplayMode) private var displayModeRaw = MenuBarDisplayMode.percent.rawValue

    var body: some View {
        RetroBatteryIcon(
            snapshot: monitor.snapshot,
            mode: MenuBarDisplayMode(rawValue: displayModeRaw) ?? .percent
        )
    }
}
