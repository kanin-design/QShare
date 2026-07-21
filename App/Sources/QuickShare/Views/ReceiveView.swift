import SwiftUI

/// Receive flow: make the Mac visible over the network. Android then finds it by
/// name in its own Quick Share device picker. The accept/decline prompt is
/// presented globally from RootView.
struct ReceiveView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
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
                    HStack(spacing: Theme.Space.sm) {
                        if model.isVisible { PulsingDot() }
                        Text(model.isVisible ? "Visible as" : "Not visible")
                            .font(.headline)
                    }
                    Text(model.isVisible ? model.deviceName : "Turn on to receive files")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.isVisible },
                    set: { _ in model.toggleVisibility() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)
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
                step(3, "Confirm the PIN matches, and the file lands in your Downloads.")
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
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
