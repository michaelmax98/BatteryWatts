import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

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
/// shimmers for a moment, and fades away (toggleable). Test buttons in the
/// panel preview each effect; Escape ends a preview. Overlay windows are
/// click-through and join every Space.
final class GlowController {
    static let shared = GlowController()

    private var windows: [NSWindow] = []
    private let state = GlowState()
    private var cancellables: Set<AnyCancellable> = []
    private var wasGlowingLow = false
    private var celebrating = false
    private var celebrationToken = 0
    private var testing = false
    private var testToken = 0
    private let escapeHotkey = EscapeHotkey()

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

    // MARK: - Live evaluation

    private func evaluate(_ snapshot: BatterySnapshot) {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: DefaultsKey.lowBatteryGlow) as? Bool ?? true
        let warn = defaults.object(forKey: DefaultsKey.warnThreshold) as? Int ?? 20
        let critical = defaults.object(forKey: DefaultsKey.criticalThreshold) as? Int ?? 10
        let celebrationOn = defaults.object(forKey: DefaultsKey.plugInCelebration) as? Bool ?? true

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
            // A real alert always wins over previews and celebrations.
            cancelCelebration()
            testing = false
            escapeHotkey.unregister()
            wasGlowingLow = true
            state.fadingOut = false
            state.level = level
            showWindows()
        } else if onPower && wasGlowingLow && celebrationOn {
            wasGlowingLow = false
            beginCelebration()
        } else {
            wasGlowingLow = false
            if !celebrating && !testing {
                hideWindows()
            }
        }
    }

    // MARK: - Previews

    func test(_ level: GlowLevel) {
        switch level {
        case .plugged:
            testing = false
            beginCelebration()
            armEscape()
        case .warning, .critical:
            cancelCelebration()
            testing = true
            state.level = level
            state.fadingOut = false
            showWindows()
            armEscape()
            scheduleTestTimeout()
        }
    }

    func endTest() {
        testing = false
        testToken += 1
        cancelCelebration()
        escapeHotkey.unregister()
        evaluate(PowerMonitor.shared.snapshot)
    }

    private func armEscape() {
        escapeHotkey.onEscape = { [weak self] in
            self?.endTest()
        }
        escapeHotkey.register()
    }

    private func scheduleTestTimeout() {
        testToken += 1
        let token = testToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.testToken == token, self.testing else { return }
            self.endTest()
        }
    }

    // MARK: - Celebration

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
            self.escapeHotkey.unregister()
            self.hideWindows()
            self.state.fadingOut = false
        }
    }

    private func cancelCelebration() {
        celebrationToken += 1
        celebrating = false
    }

    // MARK: - Windows

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

// MARK: - Escape key (registered only while a preview is showing)

/// A system-wide Escape hotkey via Carbon — works without accessibility
/// permissions, and is registered only for the duration of a glow preview
/// so it never interferes with normal Escape use.
final class EscapeHotkey {
    var onEscape: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let hotkey = Unmanaged<EscapeHotkey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    hotkey.onEscape?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x42574754), id: 1) // "BWGT"
        RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
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
        // 0 = barely-there whisper, 1 = bright and bold.
        let raw = min(max(glowWidth, 0.5), 2.0)
        let t = (raw - 0.5) / 1.5
        let ws = CGFloat(0.5 + t * 2.1)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack {
            // crisp neon core line — sharpens and brightens as intensity rises
            shape.strokeBorder(color.opacity(0.35 + 0.65 * t), lineWidth: CGFloat(2.0 + 3.0 * t))
                .blur(radius: 1.5)
            shape.strokeBorder(color.opacity(0.50 + 0.50 * t), lineWidth: 3 * ws).blur(radius: 3 * ws)
            shape.strokeBorder(color.opacity(0.30 + 0.55 * t), lineWidth: 10 * ws).blur(radius: 12 * ws)
            shape.strokeBorder(color.opacity(0.15 + 0.45 * t), lineWidth: 24 * ws).blur(radius: 30 * ws)
            // wide wash that floods inward from the edges when cranked up
            shape.strokeBorder(color.opacity(0.30 * t), lineWidth: 70 * ws).blur(radius: 70 * ws)
        }
        .padding(1)
        .opacity(pulsing ? 1.0 : (state.level == .plugged ? 0.8 : (0.45 + 0.4 * t)))
        .hueRotation(.degrees(pulsing ? (state.level == .plugged ? 25 : 10) : (state.level == .plugged ? -25 : -10)))
        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulsing)
        .opacity(state.fadingOut ? 0 : 1)
        .animation(.easeOut(duration: 0.9), value: state.fadingOut)
        .onAppear { pulsing = true }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
