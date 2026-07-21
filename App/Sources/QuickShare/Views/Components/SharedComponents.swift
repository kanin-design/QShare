import SwiftUI

/// The app's logo mark — a rounded gradient tile with the share glyph.
struct BrandMark: View {
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.brandGradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Theme.accent.opacity(0.3), radius: size * 0.16, y: 1)
    }
}

/// Small uppercase section header, optionally with a trailing accessory.
struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
            trailing
        }
    }
}

/// A soft pulsing status dot for "visible / active" state.
struct PulsingDot: View {
    var color: Color = Theme.success
    @State private var on = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().stroke(color.opacity(0.5), lineWidth: 6)
                    .scaleEffect(on ? 2.1 : 1)
                    .opacity(on ? 0 : 0.7)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    on = true
                }
            }
    }
}

/// The verification PIN, shown large so the user can match it to the other device.
struct PinBadge: View {
    let pin: String
    var body: some View {
        VStack(spacing: 4) {
            Text(pin)
                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                .tracking(8)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("Make sure this matches the code on the other device")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.md)
        .glassSurface(radius: Theme.Radius.control)
    }
}
