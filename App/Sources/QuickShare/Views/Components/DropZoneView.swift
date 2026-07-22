import SwiftUI
import UniformTypeIdentifiers

/// A glass panel you can drag files onto — or click anywhere to open the file
/// picker. Matches the app's other blue panels.
struct DropZoneView: View {
    let onFiles: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(isTargeted ? Theme.accent : .secondary)
                .symbolEffect(.bounce, value: isTargeted)

            Text(isTargeted ? "Release to add" : "Drag files here")
                .sectionStyle()
            Text("or click to choose")
                .secondaryStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .glassSurface()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(isTargeted ? Theme.accent : Color.secondary.opacity(0.35))
                .padding(4)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onTapGesture { chooseFiles() }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            loadDroppedFileURLs(providers) { urls in
                if !urls.isEmpty { onFiles(urls) }
            }
            return true
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK { onFiles(panel.urls) }
    }
}
