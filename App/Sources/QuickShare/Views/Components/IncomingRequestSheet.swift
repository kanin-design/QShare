import SwiftUI

/// Accept/decline prompt for an incoming transfer. Presented as a sheet from the
/// app root, so it appears over either tab — an incoming request is never hidden.
struct IncomingRequestSheet: View {
    let request: IncomingRequest
    let onAccept: (_ trustDevice: Bool) -> Void
    let onDecline: () -> Void

    @State private var alwaysAllow = false

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 60, height: 60)
                Image(systemName: request.device.type.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, Theme.Space.sm)

            VStack(spacing: 4) {
                Text("\(request.device.name) wants to send")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("\(request.summary) · \(request.displaySize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            PinBadge(pin: request.pin)

            Toggle(isOn: $alwaysAllow) {
                Text("Always accept from \(request.device.name)")
                    .font(.callout)
            }
            .toggleStyle(.checkbox)

            HStack(spacing: Theme.Space.md) {
                Button("Decline", role: .cancel, action: onDecline)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                Button(action: { onAccept(alwaysAllow) }) {
                    Text("Accept").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 320)
        .focusEffectDisabled()
    }
}
