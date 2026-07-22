import SwiftUI
import AppKit

/// Central design tokens. Panels are an intentional tinted glass (material +
/// blue wash) so they read the same regardless of the desktop wallpaper, and
/// adapt to light/dark.
enum Theme {

    // MARK: Color
    static let accent = Color(red: 0.16, green: 0.51, blue: 0.96)
    static let accentSecondary = Color(red: 0.35, green: 0.78, blue: 0.98)
    static let success = Color(red: 0.20, green: 0.72, blue: 0.44)
    static let danger = Color(red: 0.90, green: 0.32, blue: 0.32)

    /// Adaptive blue wash laid over the material for panels/cards.
    static let panelTint = dynamic(
        dark: NSColor(srgbRed: 0.10, green: 0.17, blue: 0.30, alpha: 0.55),
        light: NSColor(srgbRed: 0.62, green: 0.75, blue: 0.93, alpha: 0.30))

    /// Subtler wash for the whole window.
    static let windowTint = dynamic(
        dark: NSColor(srgbRed: 0.08, green: 0.13, blue: 0.24, alpha: 0.45),
        light: NSColor(srgbRed: 0.70, green: 0.81, blue: 0.95, alpha: 0.22))

    /// Hairline border for panels.
    static let hairline = dynamic(
        dark: NSColor(white: 1, alpha: 0.10),
        light: NSColor(white: 0, alpha: 0.08))

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    // MARK: Spacing (4pt scale)
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Radius
    enum Radius {
        static let card: CGFloat = 12
        static let control: CGFloat = 8
    }

    /// Brand gradient — used only for the small logo mark.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Typography (the whole system — three styles, nothing else)

// Type scale (SF Pro): 15 / 13 / 12 / 11, big → small.
extension View {
    /// Group header — most prominent.
    func sectionStyle() -> some View {
        font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
    }
    /// Card headline.
    func cardTitle() -> some View {
        font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
    }
    /// Body content.
    func primaryStyle() -> some View {
        font(.system(size: 12, weight: .regular)).foregroundStyle(.primary)
    }
    /// Muted subtext.
    func secondaryStyle() -> some View {
        font(.system(size: 11, weight: .regular)).foregroundStyle(.secondary)
    }
}

// MARK: - Surfaces

/// A tinted-glass panel with a hairline border.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
    }
}

extension View {
    /// Material + blue tint + hairline border in a continuous rounded rect.
    func glassSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                shape.fill(.regularMaterial).overlay(shape.fill(Theme.panelTint))
            }
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}
