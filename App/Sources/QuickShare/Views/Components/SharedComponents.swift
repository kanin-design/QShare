import SwiftUI
import AppKit

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
        .frame(minHeight: 19)   // fixed height so tabs share identical top geometry
        // Align the header with the card's *content*, not its outer edge — the
        // card extends further left (macOS grouped-list convention).
        .padding(.horizontal, Theme.Space.lg)
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
            case .regular: return CGSize(width: 34, height: 20)
            case .compact: return CGSize(width: 26, height: 15)
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

/// Arranges rows inside a `Card` — the only place a divider or a gap gets
/// drawn between rows, so no call site has to decide that for itself.
/// `.divider` is a settings-table shape (Services, Known senders): a hairline
/// inset under the text, the way System Settings' own toggle lists draw it —
/// not a bold rule the way our first attempt at this drew it. `.gap` is the
/// hover-highlight shape for picker-style lists (Nearby devices, Transfers),
/// where a permanent line would fight the hover background.
struct ElementList<Item: Identifiable, Row: View>: View {
    enum Separator { case divider, gap }

    let items: [Item]
    var separator: Separator = .gap
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        switch separator {
        case .divider:
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < items.count - 1 {
                        Divider()
                            .overlay(Theme.hairline.opacity(0.6))
                            .padding(.leading, 20)
                    }
                }
            }
        case .gap:
            VStack(spacing: 2) {
                ForEach(items) { row($0) }
            }
        }
    }
}

/// A row whose state IS a switch: optional icon, title, optional subtitle,
/// and an optional accessory (e.g. a "Forget" button) that sits just before
/// the switch. Every "this is on or off" row in the app is one of these —
/// Services, Known senders, the Visibility card, the incoming-request
/// "always accept" toggle — styled through these parameters rather than four
/// separate hand-written layouts. The switch is always the last thing in the
/// row, flush with the card's trailing edge, so every switch in the app —
/// regardless of what row it's in — lines up at the same size and position.
struct ToggleElement<Accessory: View>: View {
    /// The switch itself: `.system` (the real macOS switch) everywhere except
    /// the one row — visibility on the Receive tab — that's the single most
    /// glanced-at control in the app and earns the custom glass treatment.
    enum SwitchStyle { case system, glass }

    var icon: String? = nil
    var iconColor: Color = Theme.success
    let title: String
    var subtitle: String? = nil
    var subtitleColor: AnyShapeStyle = AnyShapeStyle(.secondary)
    @Binding var isOn: Bool
    var size: GlassSwitch.Size = .regular
    var switchStyle: SwitchStyle = .system
    /// Glass-only: what on/off mean beyond "enabled" — e.g. red for "not
    /// trusted" rather than the default green/danger pairing.
    var glassOnColor: Color = Theme.success
    var glassOffColor: Color = Theme.danger
    /// VoiceOver label, when the visible title alone isn't specific enough
    /// (e.g. it should name a device the title doesn't mention).
    var accessibilityLabel: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                    .frame(width: 14)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).primaryStyle().lineLimit(1)
                if let subtitle {
                    Text(subtitle).secondaryStyle().foregroundStyle(subtitleColor)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            accessory()
            switch switchStyle {
            case .system:
                // The system switch has a fixed physical size that assumes
                // System Settings' larger type; next to our much smaller type
                // scale it reads oversized, so every row pulls it down to the
                // same small size rather than varying it by row.
                Toggle(accessibilityLabel ?? title, isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            case .glass:
                GlassSwitch(isOn: $isOn, label: accessibilityLabel ?? title, size: size,
                            onColor: glassOnColor, offColor: glassOffColor)
            }
        }
        .frame(minHeight: size == .regular ? 34 : 26)
    }
}

extension ToggleElement where Accessory == EmptyView {
    init(icon: String? = nil,
         iconColor: Color = Theme.success,
         title: String,
         subtitle: String? = nil,
         subtitleColor: AnyShapeStyle = AnyShapeStyle(.secondary),
         isOn: Binding<Bool>,
         size: GlassSwitch.Size = .regular,
         switchStyle: SwitchStyle = .system,
         glassOnColor: Color = Theme.success,
         glassOffColor: Color = Theme.danger,
         accessibilityLabel: String? = nil) {
        self.init(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle,
                  subtitleColor: subtitleColor, isOn: isOn,
                  size: size, switchStyle: switchStyle,
                  glassOnColor: glassOnColor, glassOffColor: glassOffColor,
                  accessibilityLabel: accessibilityLabel, accessory: { EmptyView() })
    }
}

/// A row you tap to do something: icon, title, optional subtitle, trailing
/// view (a chevron unless overridden), hover highlight. The shape shared by
/// every "pick one of these" row — a discovered device, the QR-code
/// fallback — built once so their insets can't drift the way hand-copied
/// markup did.
struct ActionElement: View {
    let icon: String
    var iconColor: Color = Theme.accent
    let title: String
    var subtitle: String? = nil
    var subtitleColor: AnyShapeStyle = AnyShapeStyle(.secondary)
    /// Overrides the resting/hover background — e.g. a drag-and-drop target
    /// highlight. Leave nil for the default hover-only behavior.
    var tint: Color? = nil
    let action: () -> Void
    /// Replaces the default chevron when set.
    var trailing: (() -> AnyView)? = nil

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).primaryStyle()
                    if let subtitle {
                        Text(subtitle).secondaryStyle().foregroundStyle(subtitleColor)
                    }
                }
                Spacer()
                if let trailing {
                    trailing()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(tint ?? (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .onHover { hovering = $0 }
    }
}

/// The verification PIN, shown large so the user can match it to the other device.
struct PinBadge: View {
    let pin: String
    var body: some View {
        VStack(spacing: 4) {
            Text(pin)
                .font(.system(.title, design: .monospaced).weight(.semibold))
                .tracking(6)
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
