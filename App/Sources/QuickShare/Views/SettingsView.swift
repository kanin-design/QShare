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
                trustedCard
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
                    ))
                }
            }
        }
    }

    private var trustedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Trusted devices").cardTitle()
                if model.trustedDevices.isEmpty {
                    Text("None yet. Turn on “Always accept” when receiving to add one.")
                        .secondaryStyle()
                } else {
                    Text("Accepted automatically.").secondaryStyle()
                    ForEach(model.trustedDevices, id: \.self) { name in
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.success)
                            Text(name).primaryStyle()
                            Spacer()
                            Button("Remove") { model.untrust(name) }
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
