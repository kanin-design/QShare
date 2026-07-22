import SwiftUI
import AppKit

/// Fixed-size preferences form: download location, trusted devices, general.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Downloads") {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(model.downloadDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Change…", action: chooseFolder)
                }
                Text("Received files are saved here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { model.appearance },
                    set: { model.setAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Receiving") {
                Toggle("Be visible on launch", isOn: Binding(
                    get: { model.startVisible },
                    set: { model.setStartVisible($0) }
                ))
            }

            Section("Trusted devices") {
                if model.trustedDevices.isEmpty {
                    Text("No trusted devices. Turn on “Always accept” when receiving to add one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.trustedDevices, id: \.self) { name in
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(Theme.success)
                            Text(name)
                            Spacer()
                            Button("Remove") { model.untrust(name) }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 460)
        .preferredColorScheme(model.appearance.colorScheme)
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
