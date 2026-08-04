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
                    // Resting state reads Theme.textMuted directly (same
                    // source secondaryStyle uses); the copied-flash state is
                    // the real Theme.success signal.
                    .foregroundStyle(justCopied ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Theme.textMuted))
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
                // Not on a Card's glassSurface — plain `.glass` came out
                // low-contrast in Light mode here (see TransfersList's Clear
                // button). `.glassProminent` guarantees a legible solid fill.
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .font(.system(size: 11, weight: .semibold))
                .tint(Theme.orange)
                .keyboardShortcut(.cancelAction)
        }
        .multilineTextAlignment(.center)
        .padding(Theme.Space.xl)
        .frame(width: 260)
        .glassWindowBackground()
        .tint(Theme.accent)
        .preferredColorScheme(model.effectiveColorScheme)
        .focusEffectDisabled()
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BuildInfo.summary, forType: .string)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justCopied = false }
    }
}
