import AppKit

/// Window placement that respects the app's own width.
///
/// macOS's built-in "Left Half" tiling tries to make the window half the screen
/// wide; this window has a hard width cap, so the result is a clamped window in
/// roughly the right place and the tiling looks broken. These commands move and
/// grow the window vertically only, which is what "snap to the side" should mean
/// for a fixed-width utility.
@MainActor
enum WindowPlacement {

    enum Edge {
        case left, right
    }

    static func snap(to edge: Edge) {
        guard let window = targetWindow(), let screen = screen(for: window) else { return }
        let area = screen.visibleFrame          // excludes the menu bar and Dock
        var frame = window.frame

        frame.size.height = area.height
        frame.origin.y = area.minY
        frame.origin.x = edge == .left ? area.minX : area.maxX - frame.width

        window.setFrame(frame, display: true, animate: true)
    }

    static func center() {
        targetWindow()?.center()
    }

    /// Identifier of the `Window(id:)` scene in `QuickShareApp`.
    private static let mainWindowID = "main-window"

    /// The main window, identified explicitly.
    ///
    /// Matching on identifier rather than "first visible non-panel": the app
    /// also owns an `NSStatusBarWindow` for the menu-bar item, which is not an
    /// `NSPanel` and would otherwise be a candidate — snapping the status item
    /// to the side of the screen is not what anyone wants. It also keeps
    /// Settings out of scope, whatever class SwiftUI gives it.
    private static func targetWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == mainWindowID && $0.isVisible }
    }

    private static func screen(for window: NSWindow) -> NSScreen? {
        window.screen ?? NSScreen.main
    }
}
