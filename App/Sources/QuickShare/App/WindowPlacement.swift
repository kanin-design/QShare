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

    /// The window the commands should act on: whatever the user is looking at,
    /// falling back to the main window when focus is elsewhere (a sheet, or the
    /// menu bar itself).
    private static func targetWindow() -> NSWindow? {
        if let key = NSApp.keyWindow, key.isVisible, !(key is NSPanel) { return key }
        return NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
    }

    private static func screen(for window: NSWindow) -> NSScreen? {
        window.screen ?? NSScreen.main
    }
}
