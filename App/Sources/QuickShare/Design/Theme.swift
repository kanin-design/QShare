import SwiftUI

/// Central design tokens. Leans on native materials + system controls so the app
/// inherits the current macOS (Liquid Glass) look rather than fighting it.
enum Theme {

    // MARK: Color
    /// App tint. Applied once at the root via `.tint`, so standard controls
    /// (buttons, toggles, pickers) pick it up automatically.
    static let accent = Color(red: 0.16, green: 0.51, blue: 0.96)
    static let accentSecondary = Color(red: 0.35, green: 0.78, blue: 0.98)

    static let success = Color(red: 0.20, green: 0.72, blue: 0.44)

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

// MARK: - Surfaces

/// A translucent, hairline-bordered surface that reads as native glass.
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
    /// Material fill + hairline border in a continuous rounded rect.
    func glassSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
    }
}
