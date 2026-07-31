import AppKit
import SwiftUI
import Combine

enum GlowLevel: Equatable {
    case warning
    case critical
    case plugged   // brief green "power's back" shimmer when the charger lands
}

final class GlowState: ObservableObject {
    @Published var level: GlowLevel = .warning
    @Published var fadingOut = false
}

/// Shows a soft neon glow around every screen's edges while the battery is
/// below the configured thresholds — orange at the warning level, red at
/// critical. When the charger is plugged in mid-glow, the glow flips green,
/// shimmers for a moment, and fades away. Overlay windows are click-through
/// and join every Space.
final class GlowController {
    static let shared = GlowController()

    private var windows: [NSWindow] = []
    private let state = GlowState()
    private var cancellables: Set<AnyCancellable> = []
    private var wasGlowingLow = false
    private var celebrating = false
    private var celebrationToken = 0

    private init() {}

    func start() {
        PowerMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.evaluate(snapshot)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.evaluate(PowerMonitor.shared.snapshot)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildIfVisible()
            }
            .store(in: &cancellables)
    }

    private func evaluate(_ snapshot: BatterySnapshot) {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: DefaultsKey.lowBatteryGlow) as? Bool ?? true
        let warn = defaults.object(forKey: DefaultsKey.warnThreshold) as? Int ?? 20
        let critical = defaults.object(forKey: DefaultsKey.criticalThreshold) as? Int ?? 10

        let onPower: Bool
        switch snapshot.state {
        case .charging, .charged, .pluggedIdle:
            onPower = true
        default:
            onPower = false
        }

        var level: GlowLevel?
        if enabled, snapshot.state == .discharging {
            if snapshot.percent <= critical {
                level = .critical
            } else if snapshot.percent <= warn {
                level = .warning
            }
        }

        if let level {
            cancelCelebration()
            wasGlowingLow = true
            state.fadingOut = false
            state.level = level
            showWindows()
        } else if onPower && wasGlowingLow {
            wasGlowingLow = false
            beginCelebration()
        } else {
            wasGlowingLow = false
            if !celebrating {
                hideWindows()
            }
        }
    }

    private func beginCelebration() {
        celebrationToken += 1
        let token = celebrationToken
        celebrating = true
        state.level = .plugged
        state.fadingOut = false
        showWindows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.celebrationToken == token else { return }
            self.state.fadingOut = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { [weak self] in
            guard let self, self.celebrationToken == token else { return }
            self.celebrating = false
            self.hideWindows()
            self.state.fadingOut = false
        }
    }

    private func cancelCelebration() {
        celebrationToken += 1
        celebrating = false
    }

    private func showWindows() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: true)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: GlowView(state: state))
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private func hideWindows() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private func rebuildIfVisible() {
        guard !windows.isEmpty else { return }
        hideWindows()
        evaluate(PowerMonitor.shared.snapshot)
    }
}

struct GlowView: View {
    @ObservedObject var state: GlowState
    @AppStorage(DefaultsKey.glowWidth) private var glowWidth = 1.0
    @State private var pulsing = false

    private var color: Color {
        switch state.level {
        case .critical: return PowerAccent.red
        case .warning: return PowerAccent.orange
        case .plugged: return PowerAccent.green
        }
    }

    var body: some View {
        let width = CGFloat(min(max(glowWidth, 0.5), 2.0))
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack {
            shape.strokeBorder(color.opacity(0.85), lineWidth: 3 * width).blur(radius: 3 * width)
            shape.strokeBorder(color.opacity(0.55), lineWidth: 10 * width).blur(radius: 12 * width)
            shape.strokeBorder(color.opacity(0.30), lineWidth: 24 * width).blur(radius: 30 * width)
        }
        .padding(1)
        .opacity(pulsing ? 1.0 : (state.level == .plugged ? 0.75 : 0.5))
        .hueRotation(.degrees(pulsing ? (state.level == .plugged ? 25 : 10) : (state.level == .plugged ? -25 : -10)))
        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulsing)
        .opacity(state.fadingOut ? 0 : 1)
        .animation(.easeOut(duration: 0.9), value: state.fadingOut)
        .onAppear { pulsing = true }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
