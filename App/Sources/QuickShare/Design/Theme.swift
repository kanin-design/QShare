import SwiftUI
import AppKit

/// Central design tokens. Panels are tinted glass — material with a
/// deliberate, restrained blue wash, not a neutral system gray — so the app
/// still reads as its own thing rather than a System Settings clone. Adapts
/// to light/dark.
enum Theme {

    // MARK: Color
    static let accent = Color(red: 0.16, green: 0.51, blue: 0.96)
    static let success = Color(red: 0.20, green: 0.72, blue: 0.44)
    static let danger = Color(red: 0.90, green: 0.32, blue: 0.32)

    /// Blue lift over the material for panels/cards — enough to feel
    /// intentional, well short of the wash that used to drown out the accent
    /// color. Cards also use a heavier material than the window (see
    /// `glassSurface`), which does the structural half of separating a card
    /// from the window behind it; color does the rest.
    static let panelTint = dynamic(
        dark: NSColor(srgbRed: 0.14, green: 0.26, blue: 0.46, alpha: 0.22),
        light: NSColor(srgbRed: 0.55, green: 0.72, blue: 0.95, alpha: 0.28))

    /// Fainter version of the same wash for the whole window.
    static let windowTint = dynamic(
        dark: NSColor(srgbRed: 0.09, green: 0.16, blue: 0.30, alpha: 0.18),
        light: NSColor(srgbRed: 0.65, green: 0.78, blue: 0.95, alpha: 0.14))

    /// Hairline border for panels.
    static let hairline = dynamic(
        dark: NSColor(white: 1, alpha: 0.16),
        light: NSColor(white: 0, alpha: 0.12))

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

// MARK: - Typography (the whole system — three styles, nothing else)

// Type scale (SF Pro): 13 / 12 / 11 / 10, big → small.
extension View {
    /// Group header — most prominent.
    func sectionStyle() -> some View {
        font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
    }
    /// Card headline.
    func cardTitle() -> some View {
        font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
    }
    /// Body content.
    func primaryStyle() -> some View {
        font(.system(size: 11, weight: .regular)).foregroundStyle(.primary)
    }
    /// Muted subtext.
    func secondaryStyle() -> some View {
        font(.system(size: 10, weight: .regular)).foregroundStyle(.secondary)
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
    /// Neutral glass + hairline border in a continuous rounded rect. Cards use
    /// a heavier material than the window (`.thickMaterial` vs. the window's
    /// `.regularMaterial`) — that weight difference is what makes a card read
    /// as its own surface instead of blending into the background.
    func glassSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                shape.fill(.thickMaterial).overlay(shape.fill(Theme.panelTint))
            }
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}
