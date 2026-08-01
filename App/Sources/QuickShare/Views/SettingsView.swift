import SwiftUI
import AppKit

/// One row in the Services card: a toggle bound to a model property.
private struct ServiceToggle: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    /// Longer, hover-only detail — for a caveat that matters but would make
    /// the always-visible subtitle wrap messily.
    var help: String? = nil
    let isOn: Binding<Bool>
}

/// Settings, styled to match the app: tinted glass cards, the same type system,
/// and sized to its content — the window grows and shrinks as cards like
/// Known Senders appear or their lists change, rather than a fixed height.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // No explicit height anywhere in this chain: a plain VStack reports
        // its own real intrinsic size, which is what lets
        // `.windowResizability(.contentSize)` track it and resize the window
        // as cards like Known Senders appear or their list changes — driving
        // that from a self-measured `.frame(height:)` instead caused a
        // feedback loop (the frame constrained the very thing measuring it)
        // that collapsed the window to nothing.
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                section("Downloads") { downloadsCard }
                section("Appearance") { appearanceCard }
                section("Services") { servicesCard }
                if !model.knownDevices.isEmpty {
                    section("Known senders") { knownSendersCard }
                }
            }
            .padding(Theme.Space.lg)
        }
        .frame(width: 400)
        .ignoresSafeArea(.container, edges: .top)   // let the title sit on the traffic-light row
        .background(Theme.windowTint)
        .containerBackground(.regularMaterial, for: .window)
        .tint(Theme.accent)
        .preferredColorScheme(model.effectiveColorScheme)
        .focusEffectDisabled()
    }

    // Mirrors RootView's slim title: centered, vertically aligned with the
    // traffic-light buttons (28pt band), no divider.
    private var header: some View {
        Text("Settings")
            .windowHeaderStyle()
            .frame(maxWidth: .infinity, minHeight: 28)
    }

    /// A category label above its card, not a title inside it — the same
    /// grouped-list shape System Settings uses, and the one every other
    /// screen in this app already follows (`SectionHeader` + `Card`); this
    /// screen was the one holdout still putting the label inside the box.
    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: title)
            content()
        }
    }

    private var downloadsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(model.downloadDirectory.path)
                        .primaryStyle().lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Change…", action: chooseFolder)
                        // .tint alone only recolors a bordered button's label
                        // in dark appearance — light mode keeps black text
                        // regardless, so the label color needs setting directly too.
                        .tint(Theme.orange)
                        .foregroundStyle(Theme.orange)
                }
                Text("Received files are saved here.").secondaryStyle()
            }
        }
    }

    private var appearanceCard: some View {
        Card {
            // Same row shape as "Visible on launch": a label on the left,
            // the control right-aligned — not a full-width picker with no
            // label, which was the odd one out among these rows.
            HStack {
                Text("Appearance").primaryStyle()
                Spacer()
                Picker("", selection: Binding(
                    get: { model.appearance },
                    set: { model.setAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    /// Both background services as rows in one standard list card, so they
    /// line up exactly with every other multi-row card (e.g. Known senders).
    private var servicesCard: some View {
        Card {
            ElementList(items: [
                ServiceToggle(
                    id: "visible",
                    title: "Visible on launch",
                    subtitle: "Start advertising to nearby devices at startup.",
                    isOn: Binding(get: { model.startVisible },
                                  set: { model.setStartVisible($0) })),
                // Named for what it is: a local HTTP server. The qshare command
                // is one client of it, not the whole story.
                ServiceToggle(
                    id: "api",
                    title: "Local API server",
                    subtitle: "Lets the qshare command drive the app.",
                    help: "Serves 127.0.0.1:\(String(ControlServer.port)). Anything running as you can then send any file it can read.",
                    isOn: Binding(get: { model.controlAPIEnabled },
                                  set: { model.setControlAPIEnabled($0) }))
            ]) { item in
                ToggleElement(title: item.title, subtitle: item.subtitle, isOn: item.isOn)
                    .help(item.help ?? "")
            }
        }
    }

    /// The only place per-device auto-accept is managed. The incoming-request
    /// sheet has its own toggle for the moment a first-time sender needs it;
    /// this list is for reviewing and revoking trust afterward.
    private var knownSendersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Auto-accept skips the prompt for future transfers.")
                    .secondaryStyle()
                ElementList(items: model.knownDevices) { device in
                    ToggleElement(
                        icon: device.autoAccept ? "checkmark.shield.fill" : "iphone.gen3",
                        iconColor: device.autoAccept ? Theme.success : .secondary,
                        title: device.name,
                        isOn: Binding(get: { device.autoAccept },
                                      set: { model.setAutoAccept($0, for: device.name) }),
                        size: .compact,
                        accessibilityLabel: "Auto-accept from \(device.name)"
                    ) {
                        Button("Forget") { model.forget(device.name) }
                            .controlSize(.small)
                            .tint(Theme.orange)
                            .foregroundStyle(Theme.orange)
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.downloadDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            model.setDownloadDirectory(url)
        }
    }
}
