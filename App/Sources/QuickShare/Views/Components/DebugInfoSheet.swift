import SwiftUI
import AppKit

/// ⌘⇧D — exactly which build is running.
///
/// Exists so "am I testing the latest?" is answerable in one keystroke instead
/// of by inspecting timestamps. The commit is the authoritative part; the build
/// number is the part that's easy to read out loud.
struct DebugInfoSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "hammer.fill").foregroundStyle(Theme.accent)
                Text("Build info").font(.title3.weight(.semibold))
                Spacer()
            }

            DividedRowList(items: infoRows, spacing: 0, dividerInset: Theme.Space.md) { item in
                row(item.label, item.value, prominent: item.prominent)
            }
            .glassSurface(radius: Theme.Radius.control)

            if !BuildInfo.isPackaged {
                Label("Running unpackaged (swift run) — no build stamp.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }

            HStack(spacing: Theme.Space.md) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(BuildInfo.summary, forType: .string)
                }
                .controlSize(.large)

                Button(action: onClose) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 340)
        .focusEffectDisabled()
    }

    private struct InfoRow: Identifiable {
        let id: String
        let label: String
        let value: String
        var prominent = false
    }

    private var infoRows: [InfoRow] {
        [InfoRow(id: "version", label: "Version", value: BuildInfo.version),
         InfoRow(id: "build", label: "Build", value: BuildInfo.build, prominent: true),
         InfoRow(id: "commit", label: "Commit", value: BuildInfo.commit),
         InfoRow(id: "built", label: "Built", value: BuildInfo.builtAt),
         InfoRow(id: "dependencies", label: "Dependencies", value: "none")]
    }

    private func row(_ label: String, _ value: String, prominent: Bool = false) -> some View {
        HStack(spacing: Theme.Space.md) {
            Text(label).secondaryStyle()
            Spacer(minLength: Theme.Space.md)
            Text(value)
                .font(.system(size: prominent ? 14 : 12,
                              weight: prominent ? .semibold : .regular,
                              design: .monospaced))
                .foregroundStyle(prominent ? Theme.accent : .primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }
}
