import SwiftUI

/// State-driven accent colors shared by the panel, the menu bar glyph,
/// and the low-battery glow. Green on power, blue on battery, orange and
/// red once the user-configurable low-battery thresholds are crossed.
enum PowerAccent {
    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let blue = Color(red: 0.04, green: 0.52, blue: 1.00)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.04)
    static let red = Color(red: 1.00, green: 0.27, blue: 0.23)

    /// Panel accent — every state gets a color, including blue on battery.
    static func accent(for snapshot: BatterySnapshot, warn: Int, critical: Int) -> Color {
        switch snapshot.state {
        case .noBattery:
            return .secondary
        case .charging, .charged, .pluggedIdle:
            return green
        case .discharging:
            if snapshot.percent <= critical { return red }
            if snapshot.percent <= warn { return orange }
            return blue
        }
    }

    /// Menu bar fill — neutral (white/black) at normal levels on battery so
    /// the icon blends with the system ones, colored for everything else.
    static func iconFill(for snapshot: BatterySnapshot, warn: Int, critical: Int, neutral: Color) -> Color {
        switch snapshot.state {
        case .noBattery:
            return neutral.opacity(0.5)
        case .charging, .charged, .pluggedIdle:
            return green
        case .discharging:
            if snapshot.percent <= critical { return red }
            if snapshot.percent <= warn { return orange }
            return neutral
        }
    }
}
