import SwiftUI
import AppKit

/// Contents of the menu-bar item. Lets you toggle receiving, open the main
/// window, and quit — so the app is useful without its window in front.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.availableDevices.isEmpty {
            Text("Looking for devices…")
        } else {
            Text("Send to")
            ForEach(model.availableDevices) { device in
                Button {
                    sendTo(device)
                } label: {
                    Label(device.name,
                          systemImage: model.isTrusted(device.name) ? "checkmark.shield.fill" : device.type.symbol)
                }
            }
        }
        Divider()

        Toggle("Receive files (visible)", isOn: Binding(
            get: { model.isVisible },
            set: { _ in model.toggleVisibility() }
        ))

        let active = model.transfers.filter { $0.phase == .transferring }.count
        if active > 0 {
            Divider()
            Text(active == 1 ? "1 transfer in progress" : "\(active) transfers in progress")
        }

        Divider()
        Button("Open QShare") {
            NSApp.setActivationPolicy(.regular)   // restore Dock icon while the window is up
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit QShare") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Open the window straight into the drop-zone targeting `device`.
    private func sendTo(_ device: RemoteDevice) {
        NSApp.setActivationPolicy(.regular)
        model.prepareSend(to: device)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
