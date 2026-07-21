import SwiftUI
import AppKit

/// One transfer (incoming or outgoing) with progress and status. When finished
/// and multi-file, it expands to reveal individual files that open on click;
/// the row itself reveals the item(s) in Finder.
struct TransferRow: View {
    let transfer: ActiveTransfer
    let onCancel: () -> Void

    @State private var expanded = false

    private var isExpandable: Bool {
        transfer.phase == .completed && transfer.openableFiles.count > 1
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                Divider().padding(.leading, 46)
                fileList
            }
        }
        .glassSurface(radius: Theme.Radius.control)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            ZStack {
                Circle().fill(statusColor.opacity(0.15)).frame(width: 30, height: 30)
                Image(systemName: directionSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transfer.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .contentTransition(.numericText())
                }
                if transfer.phase == .transferring {
                    ProgressView(value: transfer.fraction).tint(Theme.accent)
                }
                HStack(spacing: 4) {
                    Text(transfer.deviceName); Text("·"); Text(transfer.displaySize)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            trailingControl
        }
        .padding(Theme.Space.md)
        .contentShape(Rectangle())
        .onTapGesture(perform: primaryAction)
        .help(primaryHelp)
    }

    @ViewBuilder private var trailingControl: some View {
        if transfer.phase == .transferring {
            Button(role: .cancel, action: onCancel) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel transfer")
        } else if isExpandable {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        } else if transfer.phase == .completed, transfer.revealURL != nil {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Expanded file list

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(transfer.files) { file in
                Button {
                    if let url = file.url { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: icon(for: file))
                            .foregroundStyle(file.url == nil ? Color.secondary : Theme.accent)
                            .frame(width: 20)
                        Text(file.name).font(.callout).lineLimit(1)
                            .foregroundStyle(file.url == nil ? .secondary : .primary)
                        Spacer()
                        if file.url != nil {
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.leading, 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(file.url == nil)
                .accessibilityLabel(file.url == nil ? file.name : "Open \(file.name)")
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: Actions

    private func primaryAction() {
        if isExpandable {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
        } else if transfer.phase == .completed {
            let urls = transfer.openableFiles.compactMap(\.url)
            if urls.count == 1 {
                NSWorkspace.shared.activateFileViewerSelecting(urls)   // reveal single file
            } else if !urls.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        }
    }

    private var primaryHelp: String {
        guard transfer.phase == .completed else { return "" }
        return isExpandable ? "Show files" : "Reveal in Finder"
    }

    private func icon(for file: TransferFile) -> String {
        guard let ext = file.url?.pathExtension.lowercased() ?? file.name.split(separator: ".").last.map(String.init)?.lowercased() else {
            return "doc.fill"
        }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo.fill"
        case "mp4", "mov", "avi", "mkv":                   return "film.fill"
        case "mp3", "wav", "aac", "m4a", "flac":           return "music.note"
        case "pdf":                                        return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz":              return "archivebox.fill"
        default:                                           return "doc.fill"
        }
    }

    // MARK: Status styling

    private var directionSymbol: String {
        transfer.direction == .incoming ? "arrow.down" : "arrow.up"
    }

    private var statusText: String {
        switch transfer.phase {
        case .connecting:      return "Connecting…"
        case .awaitingConsent: return "Waiting…"
        case .transferring:    return "\(Int(transfer.fraction * 100))%"
        case .completed:       return "Done"
        case .cancelled:       return "Cancelled"
        case .failed(let e):   return e
        }
    }

    private var statusColor: Color {
        switch transfer.phase {
        case .completed: return Theme.success
        case .failed:    return .red
        case .cancelled: return .secondary
        default:         return Theme.accent
        }
    }
}
