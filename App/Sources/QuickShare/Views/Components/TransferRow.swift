import SwiftUI
import AppKit

/// A compact transfer row. A small ↑/↓ arrow marks sent vs received; filename +
/// (size · device) inline; status glyph trailing. Completed multi-file transfers
/// expand to their files; single completed transfers reveal in Finder on click.
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
                Divider().padding(.leading, 38)
                fileList
            }
        }
        .glassSurface(radius: Theme.Radius.control)
    }

    // MARK: Header (~40pt)

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            directionBadge

            VStack(alignment: .leading, spacing: 1) {
                Text(transfer.title)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("\(transfer.displaySize) · \(transfer.deviceName)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: Theme.Space.sm)
            trailing
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            if transfer.phase == .transferring {
                GeometryReader { g in
                    Capsule().fill(Theme.accent)
                        .frame(width: g.size.width * transfer.fraction, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, Theme.Space.md)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: primaryAction)
        .help(transfer.phase == .completed ? (isExpandable ? "Show files" : "Reveal in Finder") : "")
    }

    private var directionBadge: some View {
        Image(systemName: transfer.direction == .incoming ? "arrow.down" : "arrow.up")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(transfer.direction == .incoming ? Theme.success : Theme.accent)
            .frame(width: 20, height: 20)
            .background((transfer.direction == .incoming ? Theme.success : Theme.accent).opacity(0.14),
                        in: Circle())
    }

    @ViewBuilder private var trailing: some View {
        switch transfer.phase {
        case .connecting, .awaitingConsent:
            ProgressView().controlSize(.small)
        case .transferring:
            HStack(spacing: 6) {
                Text("\(Int(transfer.fraction * 100))%")
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.accent).contentTransition(.numericText())
                Button(role: .cancel, action: onCancel) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).accessibilityLabel("Cancel transfer")
            }
        case .completed:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.success)
                if isExpandable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                } else if transfer.revealURL != nil {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
        case .failed(let e):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(Theme.danger).help(e)
        case .cancelled:
            Image(systemName: "minus.circle.fill").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: Expanded files

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(transfer.files) { file in
                Button {
                    if let url = file.url { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: icon(for: file))
                            .font(.system(size: 11))
                            .foregroundStyle(file.url == nil ? Color.secondary : Theme.accent)
                            .frame(width: 16)
                        Text(file.name).font(.system(size: 11)).lineLimit(1)
                            .foregroundStyle(file.url == nil ? .secondary : .primary)
                        Spacer()
                        if file.url != nil {
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.trailing, Theme.Space.md)
                    .padding(.leading, 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(file.url == nil)
                .accessibilityLabel(file.url == nil ? file.name : "Open \(file.name)")
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: Actions

    private func primaryAction() {
        if isExpandable {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
        } else if transfer.phase == .completed {
            let urls = transfer.openableFiles.compactMap(\.url)
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
    }

    private func icon(for file: TransferFile) -> String {
        let ext = (file.url?.pathExtension ?? (file.name as NSString).pathExtension).lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo.fill"
        case "mp4", "mov", "avi", "mkv":                   return "film.fill"
        case "mp3", "wav", "aac", "m4a", "flac":           return "music.note"
        case "pdf":                                        return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz":              return "archivebox.fill"
        default:                                           return "doc.fill"
        }
    }
}
