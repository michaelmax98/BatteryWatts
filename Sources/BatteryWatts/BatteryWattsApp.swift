import SwiftUI
import AppKit

@main
struct BatteryWattsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = PowerMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

enum DefaultsKey {
    static let menuBarDisplayMode = "menuBarDisplayMode"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon — this app lives entirely in the menu bar.
        NSApp.setActivationPolicy(.accessory)
        // Kick off the periodic update check (no-op under `swift run`).
        _ = UpdateChecker.shared
    }
}
