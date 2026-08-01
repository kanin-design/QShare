import SwiftUI
import AppKit

/// ⌘⌥I — exactly which build is running.
///
/// A glance-and-dismiss diagnostic, not a form: the build number and commit
/// are the only facts that actually answer "is this the latest build?", so
/// they're the whole hero — big, monospaced, tap to copy. Everything else is
/// a quiet caption underneath, not a card of equally-weighted rows.
struct DebugInfoSheet: View {
    @EnvironmentObject private var model: AppModel
    let onClose: () -> Void

    @State private var justCopied = false

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Text("Build").secondaryStyle()

            VStack(spacing: 3) {
                Text(BuildInfo.build)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())

                Text(justCopied ? "Copied to clipboard" : BuildInfo.commit)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(justCopied ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.secondary))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: copy)
            .help("Click to copy build info")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Build \(BuildInfo.build), commit \(BuildInfo.commit)")
            .accessibilityHint("Copies build info to the clipboard")
            .animation(.easeInOut(duration: 0.15), value: justCopied)

            Text("\(BuildInfo.version) · built \(BuildInfo.builtAt)")
                .secondaryStyle()

            if !BuildInfo.isPackaged {
                Label("Running unpackaged (swift run) — no build stamp.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }

            Button("Done", action: onClose)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .keyboardShortcut(.cancelAction)
        }
        .multilineTextAlignment(.center)
        .padding(Theme.Space.xl)
        .frame(width: 260)
        .background(Theme.windowTint)
        .containerBackground(.regularMaterial, for: .window)
        .tint(Theme.accent)
        .preferredColorScheme(model.appearance.colorScheme)
        .focusEffectDisabled()
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BuildInfo.summary, forType: .string)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justCopied = false }
    }
}
