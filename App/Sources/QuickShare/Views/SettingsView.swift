import SwiftUI
import AppKit

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
                knownCard
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

    /// Both background services in one card, sharing one row component so they
    /// line up exactly.
    private var servicesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Services").cardTitle()

                SettingToggleRow(
                    title: "Be visible on launch",
                    subtitle: "Start advertising to nearby devices at startup.",
                    isOn: Binding(get: { model.startVisible },
                                  set: { model.setStartVisible($0) }))

                Divider().overlay(Theme.hairline)

                // Named for what it is: a local HTTP server. The qshare command
                // is one client of it, not the whole story.
                SettingToggleRow(
                    title: "Local API server",
                    subtitle: "Serves 127.0.0.1:\(String(ControlServer.port)) so the qshare command can drive the app. Anything running as you can then send any file it can read.",
                    isOn: Binding(get: { model.controlAPIEnabled },
                                  set: { model.setControlAPIEnabled($0) }))
            }
        }
    }

    private var knownCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Known senders").cardTitle()
                if model.knownDevices.isEmpty {
                    Text("Devices appear here after you accept a transfer. Turn one on to receive from it without being asked.")
                        .secondaryStyle()
                } else {
                    Text("Auto-accept files from these devices without a prompt.")
                        .secondaryStyle()
                    ForEach(model.knownDevices) { device in
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
