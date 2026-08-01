import SwiftUI

/// Accept/decline prompt for an incoming transfer. Presented as a sheet from the
/// app root, so it appears over either tab — an incoming request is never hidden.
struct IncomingRequestSheet: View {
    @EnvironmentObject private var model: AppModel
    let request: IncomingRequest
    /// True when we've accepted from a device using this name before.
    let isKnown: Bool
    /// Accept, and whether to auto-accept from this sender from now on.
    let onAccept: (_ alwaysAccept: Bool) -> Void
    let onDecline: () -> Void

    @State private var alwaysAccept = false

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 52, height: 52)
                Image(systemName: request.device.type.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, Theme.Space.sm)

            VStack(spacing: 3) {
                Text("\(request.device.name) wants to send")
                    .sectionStyle()
                    .multilineTextAlignment(.center)
                Text("\(request.summary) · \(request.displaySize)")
                    .secondaryStyle()
            }

            PinBadge(pin: request.pin)

            if isKnown {
                Label("You've accepted from this device before", systemImage: "clock.arrow.circlepath")
                    .secondaryStyle()
            }

            // Compact switch: this is a per-device choice, not a service.
            ToggleElement(
                title: "Always accept from this device",
                subtitle: "Skip this prompt next time.",
                isOn: $alwaysAccept,
                size: .compact,
                accessibilityLabel: "Always accept from \(request.device.name)")
            .padding(.horizontal, 2)

            HStack(spacing: Theme.Space.md) {
                Button("Decline", role: .cancel, action: onDecline)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .tint(Theme.orange)
                    .foregroundStyle(Theme.orange)

                // Deliberately NOT `.defaultAction`: this sheet appears
                // unprompted and activates the app, so binding Accept to Return
                // would let a stray keystroke accept an unsolicited transfer.
                Button(action: { onAccept(alwaysAccept) }) {
                    Text("Accept").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 290)
        .background(Theme.windowTint)
        .containerBackground(.regularMaterial, for: .window)
        .tint(Theme.accent)
        .preferredColorScheme(model.effectiveColorScheme)
        .focusEffectDisabled()
    }
}
