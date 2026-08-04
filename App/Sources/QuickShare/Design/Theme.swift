import SwiftUI
import AppKit

/// Central design tokens. Panels are tinted glass — material with a
/// deliberate, restrained blue wash, not a neutral system gray — so the app
/// still reads as its own thing rather than a System Settings clone. Adapts
/// to light/dark.
enum Theme {

    // MARK: Debug color override
    //
    // Two independent gates. `#if DEBUG` means `colorDebug` is hardcoded
    // `false` in a release build (Packaging/build-app.sh release) — no
    // matter what the line below says, release can never show these.
    // `colorDebug` is a plain bool on top of that: flip it to switch every
    // token below between its real value and its debug value, in any debug
    // build, with no other edit needed. Defaults to `false` — the debug
    // palette is opt-in, not the default look of a debug build.
    //
    // Every token has its own debug color, each visually distinct from
    // every other token's — so turning this on tells you two things at
    // once: which named token is used where (nothing here looks like
    // anything else), and whether something you're looking at is actually
    // reading from `Theme` at all (a stray hardcoded color won't move).
    #if DEBUG
    static let colorDebug = false
    #else
    static let colorDebug = false
    #endif

    // MARK: Color
    static var accent: Color {
        colorDebug ? Color(red: 0.95, green: 0.25, blue: 0.55) : Color(red: 0.16, green: 0.51, blue: 0.96)
    }
    static var success: Color {
        colorDebug ? Color(red: 0.10, green: 0.80, blue: 0.75) : Color(red: 0.20, green: 0.72, blue: 0.44)
    }
    /// True red — off states, failures, the "not visible" side of the
    /// visibility toggle. Kept distinct from `orange`: merging them earlier
    /// meant the off-state couldn't read as red anymore.
    static var danger: Color {
        colorDebug ? Color(red: 0.60, green: 0.30, blue: 0.90) : Color(red: 0.90, green: 0.32, blue: 0.32)
    }
    /// Real value is just `accent` — plain-text action buttons (Change…,
    /// Forget, Clear, Done, Decline) and the "Downloads" link don't need
    /// their own hue outside debug mode. It still gets its own debug color
    /// so those call sites are visibly distinct from ones using `accent`
    /// directly, even though they render identically normally.
    static var orange: Color {
        colorDebug ? Color(red: 0.55, green: 0.60, blue: 0.68) : accent
    }
    /// QR ink: always dark navy on white outside debug mode — a QR code
    /// needs strong fixed contrast to scan, not a light/dark adaptive color.
    static var qrInk: Color {
        colorDebug ? Color(red: 0.45, green: 0.08, blue: 0.20) : Color(red: 0.09, green: 0.13, blue: 0.34)
    }

    // MARK: Text color tokens
    // The typography styles below and a handful of one-off "matches style X"
    // spots (PinBadge, badge numbers, the transfer percentage) both read
    // from these — not a hand-copied value that only looks the same. Change
    // one of these and every consumer moves together.
    static var textProminent: Color {
        colorDebug ? Color(red: 0.70, green: 0.90, blue: 0.20) : .primary
    }
    static var textMuted: Color {
        colorDebug ? Color(red: 0.95, green: 0.55, blue: 0.40) : .secondary
    }
    static var textWindowHeader: Color {
        colorDebug ? Color(red: 0.30, green: 0.70, blue: 0.95) : Color.primary.opacity(0.9)
    }

    /// Blue lift over the material for panels/cards — a wash, not the
    /// panel's opacity source. That alpha got pushed way up (0.55/0.60)
    /// specifically to compensate for `.glassEffect()`'s low native
    /// opacity; now that cards use `.thickMaterial` (which already
    /// supplies real structural opacity) plus this tint on top, the same
    /// high alpha reads as over-saturated. Back to a restrained wash.
    /// Debug mode inverts the hue (orange instead of blue), pushed further
    /// still, deliberately unmissable.
    static var panelTint: Color {
        if colorDebug {
            return dynamic(
                dark: NSColor(srgbRed: 0.85, green: 0.45, blue: 0.05, alpha: 0.55),
                light: NSColor(srgbRed: 0.98, green: 0.65, blue: 0.20, alpha: 0.55))
        }
        return dynamic(
            dark: NSColor(srgbRed: 0.14, green: 0.26, blue: 0.46, alpha: 0.22),
            light: NSColor(srgbRed: 0.55, green: 0.72, blue: 0.95, alpha: 0.28))
    }

    /// Fainter version of the same wash for the whole window.
    static var windowTint: Color {
        if colorDebug {
            return dynamic(
                dark: NSColor(srgbRed: 0.75, green: 0.35, blue: 0.02, alpha: 0.42),
                light: NSColor(srgbRed: 0.98, green: 0.70, blue: 0.30, alpha: 0.35))
        }
        return dynamic(
            dark: NSColor(srgbRed: 0.09, green: 0.16, blue: 0.30, alpha: 0.18),
            light: NSColor(srgbRed: 0.65, green: 0.78, blue: 0.95, alpha: 0.14))
    }

    /// Every drawn edge in the app: card borders and in-panel dividers alike.
    ///
    /// One token on purpose. Now that surfaces are thin enough to see the
    /// desktop through, edges — not opacity — are what separate things, so
    /// this carries more weight than the old faint hairline did. Card edges
    /// and row dividers may well want to diverge eventually; that's a split
    /// to make once there's a reason, not up front on a guess.
    static var hairline: Color {
        if colorDebug {
            return dynamic(
                dark: NSColor(srgbRed: 0.75, green: 0.55, blue: 0.95, alpha: 0.35),
                light: NSColor(srgbRed: 0.55, green: 0.30, blue: 0.85, alpha: 0.30))
        }
        return dynamic(
            dark: NSColor(white: 1, alpha: 0.34),
            light: NSColor(white: 0, alpha: 0.24))
    }

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    // MARK: Spacing (tightened grid)
    enum Space {
        static let xs: CGFloat = 3
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    // MARK: Radius
    enum Radius {
        static let card: CGFloat = 10
        static let control: CGFloat = 7
    }

}

// MARK: - Typography
// Every style here, and every one-off spot elsewhere that needs to "match"
// one of them (PinBadge, badge numbers, the transfer percentage), reads its
// color from the Theme.text* tokens above — never a hand-copied value.

// Type scale (SF Pro): 13 / 12 / 11 / 10, big → small.
extension View {
    /// Group header — most prominent. Used only via `SectionHeader`.
    /// Hierarchy comes from size/weight, not color — section, card, and body
    /// text all share the same plain text color on purpose.
    func sectionStyle() -> some View {
        font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textProminent)
    }
    /// Card headline.
    func cardTitle() -> some View {
        font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textProminent)
    }
    /// Body content.
    func primaryStyle() -> some View {
        font(.system(size: 11, weight: .regular)).foregroundStyle(Theme.textProminent)
    }
    /// Muted subtext.
    func secondaryStyle() -> some View {
        font(.system(size: 10, weight: .regular)).foregroundStyle(Theme.textMuted)
    }
    /// Window title sitting on the traffic-light row ("QShare", "Settings").
    /// Was hand-typed identically in RootView and SettingsView — pulled out
    /// once it turned out to be the exact same style defined twice.
    func windowHeaderStyle() -> some View {
        font(.system(size: 12, weight: .light)).foregroundStyle(Theme.textWindowHeader)
    }
}

// MARK: - Surfaces

/// A tinted-glass panel with a hairline border. Every card is either fixed —
/// it grows with its content — or, when `maxHeight` is set, scrollable: it
/// fills up to that height and switches to an internal glass scrollbar once
/// content actually exceeds it, instead of growing forever.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.lg
    var maxHeight: CGFloat? = nil
    @ViewBuilder var content: Content

    @State private var metrics = ScrollMetrics()
    @State private var scrollPos = ScrollPosition(edge: .top)
    private var isScrolling: Bool { metrics.content - metrics.container > 1 }

    var body: some View {
        if let maxHeight {
            ScrollView {
                content
                    .padding(padding)
                    .padding(.trailing, isScrolling ? 12 : 0)   // clear the scrollbar
                    .background(ScrollerHider())   // suppress native scroller + its background
            }
            .scrollPosition($scrollPos)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                ScrollMetrics(offset: geo.contentOffset.y,
                              content: geo.contentSize.height,
                              container: geo.containerSize.height)
            } action: { _, new in metrics = new }
            .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .leading)
            .glassSurface()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .trailing) {
                if isScrolling {
                    GlassScrollbar(offset: metrics.offset,
                                   content: metrics.content,
                                   container: metrics.container) { y in
                        scrollPos.scrollTo(y: y)
                    }
                    .padding(.trailing, 3)
                }
            }
        } else {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface()
        }
    }
}

/// Scroll geometry `Card` tracks to drive its custom scrollbar.
struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var container: CGFloat = 0
}

/// A slim vertical track with a draggable liquid-glass thumb. Reflects scroll
/// position; dragging the thumb scrolls the list (trackpad scrolling moves it too).
struct GlassScrollbar: View {
    let offset: CGFloat
    let content: CGFloat
    let container: CGFloat
    let scrollTo: (CGFloat) -> Void

    @State private var dragStartOffset: CGFloat?

    private var scrollable: CGFloat { max(content - container, 0) }

    var body: some View {
        GeometryReader { geo in
            let trackH = geo.size.height - 8            // small inset top/bottom
            let thumbH = max(32, trackH * (container / max(content, 1)))
            let maxThumbY = max(trackH - thumbH, 0)
            let thumbY = scrollable > 0 ? (offset / scrollable) * maxThumbY : 0

            ZStack(alignment: .top) {
                Capsule().fill(Color.primary.opacity(0.10))
                    .frame(width: 3, height: trackH)

                Capsule(style: .continuous)
                    // Standard material, not `.glassEffect()`: a scrollbar
                    // thumb is content-layer chrome, not navigation — see
                    // `glassSurface()`'s note on the same distinction.
                    .fill(.regularMaterial)
                    .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: 7, height: thumbH)
                    .offset(y: thumbY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let start = dragStartOffset ?? offset
                                if dragStartOffset == nil { dragStartOffset = offset }
                                let frac = maxThumbY > 0 ? value.translation.height / maxThumbY : 0
                                scrollTo(min(max(start + frac * scrollable, 0), scrollable))
                            }
                            .onEnded { _ in dragStartOffset = nil }
                    )
            }
            .frame(width: 12, height: trackH, alignment: .center)
            .padding(.vertical, 4)
        }
        .frame(width: 12)
    }
}

/// Kills the native NSScrollView scrollers (and background) so only our glass
/// panel + custom scrollbar show. Reapplies on every layout/window change because
/// SwiftUI re-adds the scroller — and with the system set to "always show scroll
/// bars", overlay/autohide are ignored, so `hasVerticalScroller = false` is the
/// only thing that actually hides it and must be re-forced.
struct ScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> HiderView { HiderView() }
    func updateNSView(_ v: HiderView, context: Context) { v.apply() }

    final class HiderView: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); apply() }
        override func layout() { super.layout(); apply() }

        func apply() {
            guard let sv = enclosingScrollView else { return }
            sv.scrollerStyle = .overlay
            sv.autohidesScrollers = true
            sv.hasVerticalScroller = false
            sv.hasHorizontalScroller = false
            sv.drawsBackground = false
        }
    }
}

extension View {
    /// A tinted-glass-*looking* panel — standard material, not real
    /// `.glassEffect()`. Per Apple's own guidance (Materials, HIG): "Don't
    /// use Liquid Glass in the content layer... Instead, use standard
    /// materials for elements in the content layer, such as app
    /// backgrounds." A card is content-layer grouping, not navigation —
    /// real Liquid Glass is reserved for the functional layer that floats
    /// above content (the mode-toggle pill, buttons), which is where this
    /// app still uses it.
    ///
    /// No material of its own — deliberately. A card sits on the window,
    /// which already supplies `.ultraThinMaterial`, so giving the card one
    /// too meant looking through two stacked materials and two tint washes.
    /// Materials compound: two "ultra thin" layers are nowhere near thin, and
    /// that — not the thickness setting — is why the wallpaper used to stop
    /// dead at the card edge. One material for the whole window, and the card
    /// separates itself with tint and a drawn border instead of by hiding
    /// what's behind it.
    func glassSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background { shape.fill(Theme.panelTint) }
            .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 1) }
    }

    /// The window-level analog of `glassSurface()` — real, genuinely
    /// see-through glass behind a window's whole root content.
    ///
    /// `.glassEffect()` turned out to be the wrong tool for the
    /// transparency itself: it's a view-level effect meant for floating
    /// controls, not hooked into the window compositor, so on its own it
    /// rendered as flat opaque white — zero desktop showing through. Real
    /// see-through vibrancy is a window property:
    /// `.containerBackground(_:for:.window)` is what actually marks the
    /// NSWindow non-opaque and blends it with what's behind the window
    /// itself. `.ultraThinMaterial`, not `.regularMaterial`: the thinnest
    /// system material, so wallpaper/desktop color genuinely shows through.
    ///
    /// The theme's own blue wash sits on top of that as a separate layer —
    /// `containerBackground` only accepts a plain `ShapeStyle`, and a
    /// `Material` can't be tinted through that API, so the tint has to be
    /// its own view. Sizing this correctly was the earlier seam bug's root
    /// cause, not "two layers" per se: `.background` proposes its content
    /// the *foreground's* own bounds, so an un-oversized tint would stop
    /// short of the top whenever content is shorter than the window. Now
    /// that the window's height genuinely tracks content (no forced
    /// minHeight, tabs stay a fixed height via RootView's top-aligned
    /// ZStack), the oversized-rectangle-clipped-by-the-real-window-edges
    /// trick lines up with `containerBackground` cleanly, no seam.
    /// One implementation, not a `#if DEBUG` variant: a debug-only override
    /// here meant debug and release rendered differently — and since the
    /// override's tint was a fixed color while `Theme.windowTint` is
    /// light/dark adaptive, Light mode diverged completely. Tuning against a
    /// build that doesn't look like the shipping one is worse than not
    /// tuning at all.
    func glassWindowBackground() -> some View {
        self
            .background {
                Rectangle().fill(Theme.windowTint)
                    .frame(width: 4000, height: 4000)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .containerBackground(.ultraThinMaterial, for: .window)
    }
}
