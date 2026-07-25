import SwiftUI

/// Accept/decline prompt for an incoming transfer. Presented as a sheet from the
/// app root, so it appears over either tab — an incoming request is never hidden.
struct IncomingRequestSheet: View {
    let request: IncomingRequest
    /// True when we've accepted from a device using this name before. A hint
    /// only — the name is unauthenticated, so it never decides anything.
    let isKnown: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

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

            if isKnown {
                Label("You've accepted from this name before", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Theme.Space.md) {
                Button("Decline", role: .cancel, action: onDecline)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                // Deliberately NOT `.defaultAction`: this sheet appears
                // unprompted and activates the app, so binding Accept to Return
                // would let a stray keystroke accept an unsolicited transfer.
                Button(action: onAccept) {
                    Text("Accept").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 320)
        .focusEffectDisabled()
    }
}
