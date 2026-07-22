import SwiftUI
import AppKit

/// The app's logo mark — renders the actual app icon (from AppIcon.icns), so
/// updating the .icns updates every logo in the UI automatically.
struct BrandMark: View {
    var size: CGFloat = 28
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Small uppercase section header, optionally with a trailing accessory.
struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.9)
            Spacer()
            trailing
        }
        .frame(minHeight: 18)   // fixed height so tabs share identical top geometry
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

/// A pure-SwiftUI on/off switch. Unlike the AppKit-backed `Toggle` hosted inside
/// a translucent material (which repaints in layers), this composites in a single
/// pass so it never flickers.
struct GlassSwitch: View {
    @Binding var isOn: Bool
    var onColor: Color = Theme.success
    var offColor: Color = Color(red: 0.85, green: 0.29, blue: 0.29)

    var body: some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(onColor) : AnyShapeStyle(offColor))
            .frame(width: 40, height: 24)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(2)
                    .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isOn)
            .contentShape(Capsule())
            .onTapGesture { isOn.toggle() }
            .accessibilityElement()
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel("Visible to nearby devices")
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
