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
        HStack(spacing: Theme.Space.sm) {
            Text(title).sectionStyle()
            Spacer()
            trailing
        }
        .frame(minHeight: 22)   // fixed height so tabs share identical top geometry
        // Align the header with the card's *content*, not its outer edge — the
        // card extends further left (macOS grouped-list convention).
        .padding(.horizontal, Theme.Space.lg)
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
    /// What this switch controls — the switch is used for several settings now,
    /// so the label can't be baked in.
    var label: String
    /// Per-item switches (one device in a list) read as subordinate to the
    /// service-level ones, so they're drawn smaller.
    var size: Size = .regular
    var onColor: Color = Theme.success
    var offColor: Color = Color(red: 0.85, green: 0.29, blue: 0.29)

    enum Size {
        case regular, compact
        var dimensions: CGSize {
            switch self {
            case .regular: return CGSize(width: 40, height: 24)
            case .compact: return CGSize(width: 32, height: 19)
            }
        }
        var knobInset: CGFloat { self == .regular ? 2 : 1.5 }
    }

    var body: some View {
        let box = size.dimensions
        Capsule()
            .fill(isOn ? AnyShapeStyle(onColor) : AnyShapeStyle(offColor))
            .frame(width: box.width, height: box.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(size.knobInset)
                    .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isOn)
            .contentShape(Capsule())
            .onTapGesture { isOn.toggle() }
            .accessibilityElement()
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(label)
    }
}

/// One switchable setting: title, explanatory subline, switch.
///
/// A single component rather than repeated layout, so every row in Settings is
/// identical by construction instead of by careful copy-paste.
struct SettingToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var size: GlassSwitch.Size = .regular

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).primaryStyle()
                Text(subtitle).secondaryStyle()
            }
            Spacer(minLength: Theme.Space.md)
            GlassSwitch(isOn: $isOn, label: title, size: size)
        }
        .frame(minHeight: size == .regular ? 40 : 32)
    }
}

/// One known sender with its auto-accept switch. Uses the compact switch: it
/// governs a single device, not a service.
struct DeviceAutoAcceptRow: View {
    let name: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: isOn ? "checkmark.shield.fill" : "iphone.gen3")
                .font(.system(size: 12))
                .foregroundStyle(isOn ? Theme.success : .secondary)
                .frame(width: 16)
            Text(name).primaryStyle().lineLimit(1)
            Spacer(minLength: Theme.Space.sm)
            Text(isOn ? "Auto" : "Ask")
                .secondaryStyle()
                .monospacedDigit()
            GlassSwitch(isOn: $isOn, label: "Auto-accept from \(name)", size: .compact)
        }
        .frame(minHeight: 32)
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
