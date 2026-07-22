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

            if !model.trustedDevices.isEmpty {
                trustedDevices
            }
        }
    }

    private var trustedDevices: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Trusted devices")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Files from these devices are accepted automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                ForEach(model.trustedDevices, id: \.self) { name in
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.success)
                        Text(name).font(.callout)
                        Spacer()
                        Button {
                            model.untrust(name)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(name) from trusted devices")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var visibilityCard: some View {
        Card {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isVisible ? "Visible as" : "Not visible")
                        .font(.system(size: 15))
                    Text(model.isVisible ? model.deviceName : "Turn on to receive files")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GlassSwitch(isOn: Binding(
                    get: { model.isVisible },
                    set: { _ in model.toggleVisibility() }
                ))
            }
        }
    }

    private var instructions: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("On your Android device")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Theme.accent, in: Circle())
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
    }
}
