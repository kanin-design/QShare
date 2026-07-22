import SwiftUI
import UniformTypeIdentifiers

/// A single discovered device in the send list — a native, hover-highlighting
/// row. You can also drag files straight onto it to send (AirDrop-style).
struct DeviceRow: View {
    let device: RemoteDevice
    let action: () -> Void
    var onDropFiles: (([URL]) -> Void)? = nil

    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: device.type.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).primaryStyle()
                    Text(dropTargeted ? "Drop to send" : device.type.rawValue.capitalized)
                        .secondaryStyle()
                        .foregroundStyle(dropTargeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                }

                Spacer()

                Image(systemName: dropTargeted ? "arrow.down.circle.fill" : "chevron.right")
                    .font(.system(size: dropTargeted ? 16 : 12, weight: .semibold))
                    .foregroundStyle(dropTargeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(dropTargeted ? Theme.accent.opacity(0.14)
                                   : (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .onHover { hovering = $0 }
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
