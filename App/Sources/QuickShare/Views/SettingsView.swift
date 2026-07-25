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
                receivingCard
                automationCard
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

    private var receivingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Receiving").cardTitle()
                HStack {
                    Text("Be visible on launch").primaryStyle()
                    Spacer()
                    GlassSwitch(isOn: Binding(
                        get: { model.startVisible },
                        set: { model.setStartVisible($0) }
                    ), label: "Be visible on launch")
                }
            }
        }
    }

    private var automationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Automation").cardTitle()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow the qshare command line").primaryStyle()
                        Text("Serves a local API on 127.0.0.1:\(String(ControlServer.port)).")
                            .secondaryStyle()
                    }
                    Spacer()
                    GlassSwitch(isOn: Binding(
                        get: { model.controlAPIEnabled },
                        set: { model.setControlAPIEnabled($0) }
                    ), label: "Allow the qshare command line")
                }
                Text("While this is on, anything running under your account can ask QShare to send any file it can read to a nearby device. Leave it off unless you use the CLI.")
                    .secondaryStyle()
            }
        }
    }

    private var knownCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Devices you've accepted from").cardTitle()
                if model.knownDevices.isEmpty {
                    Text("None yet. Names appear here after you accept a transfer.")
                        .secondaryStyle()
                } else {
                    Text("Shown as a hint on incoming requests. Every transfer still needs your approval.")
                        .secondaryStyle()
                    ForEach(model.knownDevices, id: \.self) { name in
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                            Text(name).primaryStyle()
                            Spacer()
                            Button("Forget") { model.forget(name) }
                                .controlSize(.small)
                        }
                        .padding(.vertical, 1)
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
