import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case nothing
    case percent
    case time
    case watts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nothing: return "None"
        case .percent: return "%"
        case .time: return "Time"
        case .watts: return "Watts"
        }
    }
}

/// Modern, flat battery glyph modeled on the iOS status bar battery:
/// a translucent capsule track, a solid fill sized to the charge level,
/// and the reading (percent / time left / watts) punched out of the glyph
/// as an alpha cutout — so it stays crisp over any fill color, in light or
/// dark menu bars, even if the system renders the item as a template.
struct BatteryGlyph: View {
    let snapshot: BatterySnapshot
    let mode: MenuBarDisplayMode

    private let bodyHeight: CGFloat = 13
    private let cornerRadius: CGFloat = 4

    private var bodyWidth: CGFloat {
        switch mode {
        case .nothing: return 25
        case .percent: return 27
        case .watts: return 31
        case .time: return 38
        }
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.36))

                Rectangle()
                    .fill(fillColor)
                    .frame(width: fillWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))

                readoutOverlay
                    .frame(width: bodyWidth, height: bodyHeight)
                    .blendMode(.destinationOut)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(width: bodyWidth, height: bodyHeight)
            .compositingGroup()

            // the nub
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.primary.opacity(0.5))
                .frame(width: 2, height: 4.5)
        }
        .frame(height: 15)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var readoutOverlay: some View {
        if snapshot.state != .noBattery {
            HStack(spacing: 1) {
                if snapshot.state == .charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                }
                if let readout {
                    Text(readout)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var readout: String? {
        switch mode {
        case .nothing:
            return nil
        case .percent:
            return "\(snapshot.percent)"
        case .watts:
            let magnitude = abs(snapshot.smoothedWatts)
            if magnitude < 0.05 { return "0W" }
            if magnitude >= 10 { return String(format: "%.0fW", magnitude) }
            return String(format: "%.1fW", magnitude)
        case .time:
            let minutes: Int?
            switch snapshot.state {
            case .charging: minutes = snapshot.timeToFullMinutes
            case .discharging: minutes = snapshot.timeToEmptyMinutes
            default: minutes = nil
            }
            guard let minutes else {
                // Still estimating on battery/charge; nothing to show when full or idle.
                return (snapshot.state == .charging || snapshot.state == .discharging) ? "–" : nil
            }
            let hours = minutes / 60
            let mins = minutes % 60
            if hours > 0 { return String(format: "%dh%02dm", hours, mins) }
            return "\(mins)m"
        }
    }

    private var fillWidth: CGFloat {
        guard snapshot.state != .noBattery else { return 0 }
        let fraction = max(0, min(1, Double(snapshot.percent) / 100))
        return max(4, bodyWidth * CGFloat(fraction))
    }

    private var fillColor: Color {
        switch snapshot.state {
        case .noBattery:
            return Color.primary.opacity(0.5)
        case .charging, .charged, .pluggedIdle:
            return .green
        case .discharging:
            return snapshot.percent <= 20 ? .red : .primary
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: PowerMonitor
    @AppStorage(DefaultsKey.menuBarDisplayMode) private var displayModeRaw = MenuBarDisplayMode.percent.rawValue

    var body: some View {
        BatteryGlyph(
            snapshot: monitor.snapshot,
            mode: MenuBarDisplayMode(rawValue: displayModeRaw) ?? .percent
        )
    }
}
