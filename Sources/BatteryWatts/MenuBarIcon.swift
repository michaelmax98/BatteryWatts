import SwiftUI
import AppKit

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

/// Flat, modern battery glyph modeled on the iOS status bar battery:
/// translucent capsule track, solid fill sized to the charge level, and the
/// reading (percent / time / watts) punched out of the shape as a cutout.
///
/// The glyph is drawn offscreen into an image before it reaches the menu
/// bar — the status item pipeline drops blend modes when compositing live
/// views (which erased the battery shape entirely in 1.1.0), but it shows
/// pre-rendered images pixel-for-pixel.
struct BatteryGlyph: View {
    let snapshot: BatterySnapshot
    let mode: MenuBarDisplayMode
    let darkMenuBar: Bool
    let warn: Int
    let critical: Int

    private let bodyHeight: CGFloat = 13
    private let cornerRadius: CGFloat = 4
    // One fixed size for every display mode so the menu bar never shifts.
    private let bodyWidth: CGFloat = 36

    private var baseColor: Color { darkMenuBar ? .white : .black }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(baseColor.opacity(0.35))

                Rectangle()
                    .fill(fillColor)
                    .frame(width: fillWidth)

                readoutOverlay
                    .frame(width: bodyWidth, height: bodyHeight)
                    .blendMode(.destinationOut)
            }
            .frame(width: bodyWidth, height: bodyHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .compositingGroup()

            // the nub
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(baseColor.opacity(0.5))
                .frame(width: 2, height: 4.5)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 1)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var readoutOverlay: some View {
        if snapshot.state != .noBattery {
            HStack(spacing: 1) {
                if snapshot.state == .charging && mode != .watts {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                }
                if let readout {
                    Text(readout)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
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
            let number = magnitude >= 10
                ? String(format: "%.0f", magnitude)
                : String(format: "%.1f", magnitude)
            switch snapshot.state {
            case .charging:
                return "▴\(number)W"
            case .discharging:
                return "▾\(number)W"
            default:
                return "\(number)W"
            }
        case .time:
            let minutes: Int?
            switch snapshot.state {
            case .charging: minutes = snapshot.timeToFullMinutes
            case .discharging: minutes = snapshot.timeToEmptyMinutes
            default: minutes = nil
            }
            guard let minutes else {
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
        PowerAccent.iconFill(for: snapshot, warn: warn, critical: critical, neutral: baseColor)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: PowerMonitor
    @AppStorage(DefaultsKey.menuBarDisplayMode) private var displayModeRaw = MenuBarDisplayMode.percent.rawValue
    @AppStorage(DefaultsKey.warnThreshold) private var warnThreshold = 20
    @AppStorage(DefaultsKey.criticalThreshold) private var criticalThreshold = 10
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let glyph = BatteryGlyph(
            snapshot: monitor.snapshot,
            mode: MenuBarDisplayMode(rawValue: displayModeRaw) ?? .percent,
            darkMenuBar: colorScheme == .dark,
            warn: warnThreshold,
            critical: criticalThreshold
        )
        if let image = renderedImage(for: glyph) {
            Image(nsImage: image)
        } else {
            glyph
        }
    }

    private func renderedImage(for glyph: BatteryGlyph) -> NSImage? {
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = max(2, NSScreen.main?.backingScaleFactor ?? 2)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }
}
