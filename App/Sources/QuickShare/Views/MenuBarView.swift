import SwiftUI
import AppKit

/// Contents of the menu-bar item. Lets you toggle receiving, open the main
/// window, and quit — so the app is useful without its window in front.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Receive files (visible)", isOn: Binding(
            get: { model.isVisible },
            set: { _ in model.toggleVisibility() }
        ))

        let active = model.transfers.filter { $0.phase == .transferring }.count
        if active > 0 {
            Divider()
            Text(active == 1 ? "1 transfer in progress" : "\(active) transfers in progress")
        }
        if !model.trustedDevices.isEmpty {
            Divider()
            Text("Trusted: \(model.trustedDevices.joined(separator: ", "))")
        }

        Divider()
        Button("Open QuickShare") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit QuickShare") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
