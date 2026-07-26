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
                // A single-column utility: it has one sensible width and a bit of
                // slack either side. Height stays free — that's where transfers
                // accumulate.
                .frame(minWidth: 440, idealWidth: 460, maxWidth: 620,
                       minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)   // honour the width bounds above
        .defaultSize(width: 460, height: 700)
        .commands { AppCommands(model: model) }

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

    // Note on the Help menu: `CommandGroup(replacing: .help) {}` removes its one
    // dead item ("QShare Help"), leaving only the system search field. The menu
    // itself can't be removed from here — AppKit reinstates it after launch, and
    // stripping it from NSApp.mainMenu (also via NSApp.helpMenu) was verified
    // not to stick. Left in place rather than fought with a timer.

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the window drops the app to a menu-bar-only agent (no Dock icon).
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}
