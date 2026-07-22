import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop target plus a "Choose Files…" picker. Shown after a device is
/// picked. Reports chosen file URLs upward.
struct DropZoneView: View {
    let onFiles: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(isTargeted ? Theme.accent : .secondary)
                .symbolEffect(.bounce, value: isTargeted)

            VStack(spacing: 2) {
                Text(isTargeted ? "Release to add" : "Drag files here")
                    .font(.system(size: 15))
                Text("or")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button("Choose Files…", action: chooseFiles)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(isTargeted ? Theme.accent.opacity(0.10) : Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isTargeted ? Theme.accent : Color.primary.opacity(0.15))
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            onFiles(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        loadDroppedFileURLs(providers) { urls in
            if !urls.isEmpty { onFiles(urls) }
        }
        return true
    }
}
