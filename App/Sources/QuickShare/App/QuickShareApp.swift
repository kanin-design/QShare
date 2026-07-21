import SwiftUI
import AppKit

@main
struct QuickShareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("QuickShare") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 440, idealWidth: 460, maxWidth: 560,
                       minHeight: 600, idealHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

/// Ensures the app behaves as a normal foreground app when launched via
/// `swift run` (no bundle). Harmless when run from a proper .app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
