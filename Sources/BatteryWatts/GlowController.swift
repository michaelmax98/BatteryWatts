import AppKit
import SwiftUI
import Combine

enum GlowLevel: Equatable {
    case warning
    case critical
}

final class GlowState: ObservableObject {
    @Published var level: GlowLevel = .warning
}

/// Shows a soft neon glow around every screen's edges while the battery is
/// below the configured thresholds — orange at the warning level, red at
/// critical. The overlay windows are click-through and join every Space.
final class GlowController {
    static let shared = GlowController()

    private var windows: [NSWindow] = []
    private let state = GlowState()
    private var cancellables: Set<AnyCancellable> = []

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

        var level: GlowLevel?
        if enabled, snapshot.state == .discharging {
            if snapshot.percent <= critical {
                level = .critical
            } else if snapshot.percent <= warn {
                level = .warning
            }
        }

        if let level {
            state.level = level
            showWindows()
        } else {
            hideWindows()
        }
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
    @State private var pulsing = false

    private var color: Color {
        state.level == .critical ? PowerAccent.red : PowerAccent.orange
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack {
            shape.strokeBorder(color.opacity(0.85), lineWidth: 3).blur(radius: 3)
            shape.strokeBorder(color.opacity(0.55), lineWidth: 10).blur(radius: 12)
            shape.strokeBorder(color.opacity(0.30), lineWidth: 24).blur(radius: 30)
        }
        .padding(1)
        .opacity(pulsing ? 1.0 : 0.5)
        .hueRotation(.degrees(pulsing ? 10 : -10))
        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulsing)
        .onAppear { pulsing = true }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
