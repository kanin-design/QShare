import SwiftUI
import AppKit

/// The slim window title that sits on the traffic-light row. Both windows draw
/// it identically and only the string differs, so the 28pt band that lines it
/// up with the traffic lights lives here instead of being restated per window.
struct WindowHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .windowHeaderStyle()
            .frame(maxWidth: .infinity, minHeight: 28)
    }
}

/// Small uppercase section header, optionally with a trailing accessory.
/// Generic over the accessory rather than taking an `AnyView`: the erasure was
/// costing every caller a wrapper at the call site and buying nothing.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Text(title).sectionStyle()
            Spacer()
            trailing()
        }
        .frame(minHeight: 19)   // fixed height so tabs share identical top geometry
        // Align the header with the card's *content*, not its outer edge — the
        // card extends further left (macOS grouped-list convention).
        .padding(.horizontal, Theme.Space.lg)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title, trailing: { EmptyView() })
    }
}

/// A pure-SwiftUI on/off switch. Unlike the AppKit-backed switch hosted inside
/// a translucent material (which repaints in layers), this composites in a
/// single pass so it never flickers.
///
/// A `ToggleStyle` rather than a standalone view: `Toggle` then supplies the
/// keyboard activation, button role and accessibility wiring that the old
/// `.onTapGesture` capsule had to fake by hand — and both switches in the app
/// become the same `Toggle` with a different style attached.
struct GlassToggleStyle: ToggleStyle {
    var density: Theme.Density = .regular
    var onColor: Color = Theme.switchOn
    var offColor: Color = Theme.switchOff

    func makeBody(configuration: Configuration) -> some View {
        let box = density.switchSize
        return Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(onColor) : AnyShapeStyle(offColor))
                .frame(width: box.width, height: box.height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .padding(density.knobInset)
                        .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.72),
                           value: configuration.isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

extension ToggleStyle where Self == GlassToggleStyle {
    static var glass: GlassToggleStyle { GlassToggleStyle() }

    static func glass(density: Theme.Density,
                      on: Color = Theme.switchOn,
                      off: Color = Theme.switchOff) -> GlassToggleStyle {
        GlassToggleStyle(density: density, onColor: on, offColor: off)
    }
}

/// Arranges rows inside a `Card`, the one place every row list in the app
/// (Services, Known senders, Nearby devices, Transfers) gets its shape from.
/// Every row but the last carries a hairline on its own bottom edge — an
/// overlay, not a separately inserted spacer view, so it draws into the
/// existing row spacing rather than adding any height of its own. Faint by
/// design: System Settings' own row rule is barely there, not a bold line.
struct ElementList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                    .overlay(alignment: .bottom) {
                        if index < items.count - 1 {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 0.5)
                                .padding(.leading, 20)
                                .padding(.trailing, 4)
                        }
                    }
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
    /// Neutral by default — a row icon carries no status of its own, so the
    /// one row that means something by it (a trusted sender) says so
    /// explicitly rather than inheriting a green nothing else wants.
    var iconColor: Color = .secondary
    let title: String
    var subtitle: String? = nil
    var subtitleColor: AnyShapeStyle = AnyShapeStyle(.secondary)
    @Binding var isOn: Bool
    var density: Theme.Density = .regular
    var switchStyle: SwitchStyle = .system
    /// Glass-only: what on/off mean beyond "enabled" — e.g. red for "not
    /// trusted" rather than the default switchOn/switchOff pairing.
    var glassOnColor: Color = Theme.switchOn
    var glassOffColor: Color = Theme.switchOff
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
            toggle
        }
        .frame(minHeight: density.rowMinHeight)
    }

    /// Both variants are the same `Toggle` under a different style — the only
    /// thing that differs is which switch gets drawn. The visible title is
    /// drawn by the row above, so the label here is purely for VoiceOver.
    @ViewBuilder private var toggle: some View {
        switch switchStyle {
        case .system:
            // The system switch has a fixed physical size that assumes System
            // Settings' larger type; next to our much smaller type scale it
            // reads oversized, so every row pulls it down to the same small
            // size rather than varying it by row.
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(accessibilityLabel ?? title)
        case .glass:
            Toggle("", isOn: $isOn)
                .toggleStyle(.glass(density: density, on: glassOnColor, off: glassOffColor))
                .labelsHidden()
                .accessibilityLabel(accessibilityLabel ?? title)
        }
    }
}

extension ToggleElement where Accessory == EmptyView {
    init(icon: String? = nil,
         iconColor: Color = .secondary,
         title: String,
         subtitle: String? = nil,
         subtitleColor: AnyShapeStyle = AnyShapeStyle(.secondary),
         isOn: Binding<Bool>,
         density: Theme.Density = .regular,
         switchStyle: SwitchStyle = .system,
         glassOnColor: Color = Theme.switchOn,
         glassOffColor: Color = Theme.switchOff,
         accessibilityLabel: String? = nil) {
        self.init(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle,
                  subtitleColor: subtitleColor, isOn: isOn,
                  density: density, switchStyle: switchStyle,
                  glassOnColor: glassOnColor, glassOffColor: glassOffColor,
                  accessibilityLabel: accessibilityLabel, accessory: { EmptyView() })
    }
}

/// The default trailing affordance on an `ActionElement` — its own type so the
/// generic form can name it as the default `Trailing`.
struct ActionChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}

/// A row you tap to do something: icon, title, optional subtitle, trailing
/// view (a chevron unless overridden), hover highlight. The shape shared by
/// every "pick one of these" row — a discovered device, the QR-code
/// fallback — built once so their insets can't drift the way hand-copied
/// markup did.
struct ActionElement<Trailing: View>: View {
    let icon: String
    var iconColor: Color = Theme.accent
    let title: String
    var subtitle: String? = nil
    var subtitleColor: AnyShapeStyle = AnyShapeStyle(.secondary)
    /// Overrides the resting/hover background — e.g. a drag-and-drop target
    /// highlight. Leave nil for the default hover-only behavior.
    var tint: Color? = nil
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

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
                trailing()
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

extension ActionElement where Trailing == ActionChevron {
    init(icon: String,
         iconColor: Color = Theme.accent,
         title: String,
         subtitle: String? = nil,
         subtitleColor: AnyShapeStyle = AnyShapeStyle(.secondary),
         tint: Color? = nil,
         action: @escaping () -> Void) {
        self.init(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle,
                  subtitleColor: subtitleColor, tint: tint, action: action,
                  trailing: { ActionChevron() })
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
                // The most prominent text in this sheet — reads Theme.textProminent
                // directly (same source sectionStyle uses), kept at its own
                // large monospaced size for digit legibility.
                .foregroundStyle(Theme.textProminent)
                .contentTransition(.numericText())
            Text("Make sure this matches the code on the other device")
                .secondaryStyle()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.md)
        .glassSurface(radius: Theme.Radius.control)
    }
}
