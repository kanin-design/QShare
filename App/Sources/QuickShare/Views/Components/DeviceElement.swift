import SwiftUI
import UniformTypeIdentifiers

/// A single discovered device in the send list. An `ActionElement` — tap to
/// select it — that also accepts a drag-and-drop of files (AirDrop-style),
/// swapping its subtitle/trailing/tint to show the drop target while one is
/// dragged over it.
struct DeviceElement: View {
    let device: RemoteDevice
    let action: () -> Void
    var onDropFiles: (([URL]) -> Void)? = nil

    @State private var dropTargeted = false

    var body: some View {
        ActionElement(
            icon: device.type.symbol,
            title: device.name,
            subtitle: dropTargeted ? "Drop to send" : device.type.rawValue.capitalized,
            subtitleColor: dropTargeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary),
            tint: dropTargeted ? Theme.accent.opacity(0.14) : nil,
            action: action,
            trailing: {
                Image(systemName: dropTargeted ? "arrow.down.circle.fill" : "chevron.right")
                    .font(.system(size: dropTargeted ? 14 : 11, weight: .semibold))
                    .foregroundStyle(dropTargeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            }
        )
        .accessibilityLabel("Send to \(device.name), \(device.type.rawValue)")
        .modifier(DropIfAvailable(enabled: onDropFiles != nil, isTargeted: $dropTargeted) { providers in
            loadDroppedFileURLs(providers) { urls in
                if !urls.isEmpty { onDropFiles?(urls) }
            }
            return true
        })
    }
}

/// Only attach an `onDrop` when a handler is supplied (avoids swallowing drops
/// on rows that don't send).
private struct DropIfAvailable: ViewModifier {
    let enabled: Bool
    @Binding var isTargeted: Bool
    let perform: ([NSItemProvider]) -> Bool

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: perform)
        } else {
            content
        }
    }
}
