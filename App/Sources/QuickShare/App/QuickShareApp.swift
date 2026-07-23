import SwiftUI
import AppKit

@main
struct QuickShareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // A single Window (not WindowGroup) so "Open" focuses the one window
        // instead of spawning duplicates.
        Window("QShare", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)   // freely resizable; content fills + scrolls

        // Menu-bar presence: usable without the window in front.
        MenuBarExtra {
            MenuBarView().environmentObject(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

/// Ensures the app behaves as a normal foreground app when launched via
/// `swift run` (no bundle). Harmless when run from a proper .app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)   // show the window + Dock icon on launch
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the window drops the app to a menu-bar-only agent (no Dock icon).
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}
