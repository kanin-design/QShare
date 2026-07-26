import SwiftUI
import AppKit

/// Receive flow: make the Mac visible over the network. Android then finds it by
/// name in its own Quick Share device picker. The accept/decline prompt is
/// presented globally from RootView.
struct ReceiveView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            // Mirrors Send's "NEARBY DEVICES" slot so content lands at the same Y.
            SectionHeader(title: "Visibility")

            visibilityCard

            if model.isVisible {
                instructions
            }

            if !model.knownDevices.isEmpty {
                knownDevices
            }
        }
    }

    private var knownDevices: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Known senders").cardTitle()
                Text("Turn one on to receive from it without a prompt.")
                    .secondaryStyle()
                ScrollView {
                    VStack(spacing: Theme.Space.xs) {
                        ForEach(model.knownDevices) { device in
                            DeviceAutoAcceptRow(
                                name: device.name,
                                isOn: Binding(
                                    get: { device.autoAccept },
                                    set: { model.setAutoAccept($0, for: device.name) }))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var visibilityCard: some View {
        Card {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isVisible ? "Visible as" : "Not visible").cardTitle()
                    Text(model.isVisible ? model.deviceName : "Turn on to receive files")
                        .secondaryStyle()
                }
                Spacer()
                GlassSwitch(isOn: Binding(
                    get: { model.isVisible },
                    set: { _ in model.toggleVisibility() }
                ), label: "Visible to nearby devices")
            }
        }
    }

    private var instructions: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("On your Android device").cardTitle()
                step(1, "Select a file and tap Share, then Quick Share.")
                step(2, "Choose “\(model.deviceName)” from the list of nearby devices.")
                step(3, "Confirm the PIN, and files land in [\(model.downloadDirectory.lastPathComponent)](qshare://folder).")
            }
            .tint(Theme.accent)
            .environment(\.openURL, OpenURLAction { _ in
                NSWorkspace.shared.open(model.downloadDirectory)
                return .handled
            })
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Text("\(n)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Color.primary.opacity(0.08), in: Circle())
            Text(text).primaryStyle()
            Spacer(minLength: 0)
        }
    }
}
