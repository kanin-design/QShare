import SwiftUI
import AppKit

/// A compact transfer row. A small ↑/↓ arrow marks sent vs received; filename +
/// (size · device) inline; status glyph trailing. Completed multi-file transfers
/// expand to their files; single completed transfers reveal in Finder on click.
struct TransferRow: View {
    let transfer: ActiveTransfer
    let onCancel: () -> Void

    @State private var expanded = false
    @State private var hovering = false

    private var isExpandable: Bool {
        transfer.phase == .completed && transfer.openableFiles.count > 1
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                Divider().overlay(Theme.hairline).padding(.leading, 34)
                fileList
            }
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hovering = $0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            directionBadge

            VStack(alignment: .leading, spacing: 1) {
                Text(transfer.title)
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text("\(transfer.displaySize) · \(transfer.deviceName)")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: Theme.Space.sm)
            trailing
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: primaryAction)
        .help(transfer.phase == .completed ? (isExpandable ? "Show files" : "Reveal in Finder") : "")
    }

    /// The direction arrow doubles as the progress indicator: its own ring
    /// fills in while transferring, instead of a separate progress bar
    /// competing for space in an already-compact row.
    private var directionBadge: some View {
        let color = transfer.direction == .incoming ? Theme.success : Theme.accent
        return ZStack {
            if transfer.phase == .transferring {
                Circle().stroke(color.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(transfer.fraction, 0.02))
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: transfer.fraction)
            } else {
                Circle().fill(color.opacity(0.14))
            }
            Image(systemName: transfer.direction == .incoming ? "arrow.down" : "arrow.up")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 18, height: 18)
    }

    @ViewBuilder private var trailing: some View {
        switch transfer.phase {
        case .connecting, .awaitingConsent:
            ProgressView().controlSize(.small)
        case .transferring:
            HStack(spacing: 5) {
                Text("\(Int(transfer.fraction * 100))%")
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary).contentTransition(.numericText())
                Button(role: .cancel, action: onCancel) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).accessibilityLabel("Cancel transfer")
            }
        case .completed:
            // One trailing slot, not two: the checkmark is the resting state,
            // and swaps to the reveal affordance on hover instead of the row
            // permanently showing both.
            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.success)
                    .opacity(hovering ? 0 : 1)
                if isExpandable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .opacity(hovering ? 1 : 0)
                } else if transfer.revealURL != nil {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: hovering)
        case .failed(let e):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(Theme.danger).help(e)
        case .cancelled:
            Image(systemName: "minus.circle.fill").font(.system(size: 11)).foregroundStyle(.secondary)
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
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text(file.name).font(.system(size: 10)).lineLimit(1)
                            .foregroundStyle(file.url == nil ? .secondary : .primary)
                        Spacer()
                        if file.url != nil {
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.trailing, Theme.Space.md)
                    .padding(.leading, 34)
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
