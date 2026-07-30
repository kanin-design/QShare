import SwiftUI
import AppKit

/// One row in the Services card: a toggle bound to a model property.
private struct ServiceToggle: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>
}

/// Settings, styled to match the app: tinted glass cards, the same type system,
/// and scrollable so long lists never overflow the fixed-size window.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                downloadsCard
                appearanceCard
                servicesCard
                if !model.knownDevices.isEmpty {
                    knownSendersCard
                }
            }
            .padding(Theme.Space.lg)
        }
        .scrollIndicators(.hidden)
        .frame(width: 460, height: 520)
        .background(Theme.windowTint)
        .containerBackground(.regularMaterial, for: .window)
        .tint(Theme.accent)
        .preferredColorScheme(model.appearance.colorScheme)
        .focusEffectDisabled()
    }

    private var downloadsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Downloads").cardTitle()
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(model.downloadDirectory.path)
                        .secondaryStyle().lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Change…", action: chooseFolder)
                }
                Text("Received files are saved here.").secondaryStyle()
            }
        }
    }

    private var appearanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Appearance").cardTitle()
                Picker("", selection: Binding(
                    get: { model.appearance },
                    set: { model.setAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    /// Both background services as rows in one standard list card, so they
    /// line up exactly with every other multi-row card (e.g. Known senders).
    private var servicesCard: some View {
        RowListCard(title: "Services", items: [
            ServiceToggle(
                id: "visible",
                title: "Be visible on launch",
                subtitle: "Start advertising to nearby devices at startup.",
                isOn: Binding(get: { model.startVisible },
                              set: { model.setStartVisible($0) })),
            // Named for what it is: a local HTTP server. The qshare command
            // is one client of it, not the whole story.
            ServiceToggle(
                id: "api",
                title: "Local API server",
                subtitle: "Serves 127.0.0.1:\(String(ControlServer.port)) so the qshare command can drive the app. Anything running as you can then send any file it can read.",
                isOn: Binding(get: { model.controlAPIEnabled },
                              set: { model.setControlAPIEnabled($0) }))
        ]) { item in
            SettingToggleRow(title: item.title, subtitle: item.subtitle, isOn: item.isOn)
        }
    }

    /// Settings is the only place this list lives now — the Receive tab's copy
    /// was removed since the incoming-request sheet already offers the same
    /// auto-accept toggle at the moment it's actually useful.
    private var knownSendersCard: some View {
        RowListCard(
            title: "Known senders",
            description: "Turn on auto-accept to skip the prompt for a sender's future transfers.",
            items: model.knownDevices
        ) { device in
            HStack(spacing: Theme.Space.sm) {
                DeviceAutoAcceptRow(
                    name: device.name,
                    isOn: Binding(
                        get: { device.autoAccept },
                        set: { model.setAutoAccept($0, for: device.name) }))
                Button("Forget") { model.forget(device.name) }
                    .controlSize(.small)
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
