import SwiftUI
import AppKit

@main
struct QuickShareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // A single Window (not WindowGroup) so "Open" focuses the one window
        // instead of spawning duplicates.
        //
        // id is "main-window", not "main": macOS autosaves a window's frame
        // per id across launches (same lesson as the Settings window below).
        // Every manual resize made while testing real resizability got
        // persisted under "main" and then restored on the next launch
        // regardless of content — a giant window with a huge empty area
        // below sparse content. A fresh id starts with no saved frame to
        // inherit.
        Window("QShare", id: "main-window") {
            RootView()
                .environmentObject(model)
                // A single-column utility, genuinely user-resizable in both
                // axes — with no height range at all (the previous state),
                // `.windowResizability(.contentSize)` pins height to the
                // content's ideal size with zero slack, which reads as the
                // window not being resizable at all, not just vertically
                // capped. minWidth is a floor for legibility, not a forced
                // starting size — the window still opens sized to its
                // actual content (no minHeight floor), and can be dragged
                // taller for a longer transfers list or shorter down to
                // minHeight.
                //
                // alignment: .top is not optional here: RootView's own
                // `.frame(alignment: .top)` only governs how its content
                // sits inside *that* frame call — it doesn't survive being
                // re-wrapped by this outer, differently-sized frame. Without
                // an alignment here too, any time the window ends up taller
                // than the content's natural size (a manual resize, a
                // restored frame from a previous session), SwiftUI centers
                // the content in the extra space by default — a growing gap
                // above the header instead of the extra room landing below.
                .frame(minWidth: 360, idealWidth: 460, maxWidth: 640,
                       minHeight: 280, maxHeight: 900, alignment: .top)
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

        // A Window, not the Settings scene: Settings windows keep an opaque
        // native title bar and toolbar that `.windowStyle(.hiddenTitleBar)`
        // cannot override, so it can never match the rest of the app's glass
        // chrome. A plain Window with the same style RootView uses can.
        //
        // id is "settings-panel", not "settings": macOS persists window
        // frames per id across launches, and an earlier build briefly had a
        // layout bug that saved a collapsed frame under "settings" — every
        // relaunch kept restoring that broken size no matter what the
        // current layout code did. A fresh id has no saved frame to inherit.
        Window("Settings", id: "settings-panel") {
            SettingsView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 520)
    }
}

/// Ensures the app behaves as a normal foreground app when launched via
/// `swift run` (no bundle). Harmless when run from a proper .app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)   // show the window + Dock icon on launch
        NSApp.activate(ignoringOtherApps: true)
    }

    // The Help menu itself can't be removed from here: AppKit reinstates it
    // after launch, and stripping it via NSApp.mainMenu or NSApp.helpMenu
    // doesn't stick. `CommandGroup(replacing: .help) {}` above is what
    // actually removes its one dead item ("QShare Help"), leaving just the
    // system search field.

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the window drops the app to a menu-bar-only agent (no Dock icon).
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}
