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

extension View {
    /// The one expressive style: slim, airy, ~90% white. Section headers + wordmark.
    func sectionStyle() -> some View {
        font(.system(size: 14, weight: .light)).foregroundStyle(.primary.opacity(0.9))
    }
    /// The first line of every card — its headline. Identical across all cards.
    func cardTitle() -> some View {
        font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
    }
    /// Main content text (device names, prompts, file names, steps).
    func primaryStyle() -> some View {
        font(.system(size: 13, weight: .regular)).foregroundStyle(.primary.opacity(0.9))
    }
    /// Supporting text (subtitles, sizes, hints, in-card labels).
    func secondaryStyle() -> some View {
        font(.system(size: 12, weight: .regular)).foregroundStyle(.secondary)
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
