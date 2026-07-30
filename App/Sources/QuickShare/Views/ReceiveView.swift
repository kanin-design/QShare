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
        }
    }

    private var visibilityCard: some View {
        Card {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).cardTitle()
                    Text(statusDetail)
                        .secondaryStyle()
                        .foregroundStyle(model.visibilityStatus == .failed
                                         ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(.secondary))
                }
                Spacer()

                // Bound to intent, so it moves the instant it's clicked rather
                // than waiting on mDNS.
                GlassSwitch(isOn: Binding(
                    get: { model.wantsVisible },
                    set: { model.setVisible($0) }
                ), label: "Visible to nearby devices")
            }
            .animation(.easeInOut(duration: 0.2), value: model.visibilityStatus)
        }
    }

    private var statusTitle: String {
        switch model.visibilityStatus {
        case .on:       return "Visible as"
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        case .failed:   return "Couldn't become visible"
        case .off:      return "Not visible"
        }
    }

    private var statusDetail: String {
        switch model.visibilityStatus {
        case .on:       return model.deviceName
        case .starting: return "Announcing on the local network"
        case .stopping: return "Withdrawing from the network"
        case .failed:   return "Check that QShare is allowed on your local network."
        case .off:      return "Turn on to receive files"
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
