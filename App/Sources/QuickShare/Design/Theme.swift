import SwiftUI
import AppKit

/// Central design tokens. Panels are tinted glass — material with a
/// deliberate, restrained blue wash, not a neutral system gray — so the app
/// still reads as its own thing rather than a System Settings clone. Adapts
/// to light/dark.
enum Theme {

    // MARK: Color
    static let accent = Color(red: 0.16, green: 0.51, blue: 0.96)

    // MARK: Status
    // The system's own red and green rather than hand-mixed sRGB triples, so
    // they track the user's Increase Contrast and Differentiate Without Color
    // settings — which a fixed literal cannot. Strictly "this worked" / "this
    // went wrong"; anything that merely wants to *look* green or red uses a
    // role token below instead.
    static let success = Color.green
    /// Failures, and the "not visible" side of the visibility toggle. Kept
    /// distinct from `orange` below: merging them earlier meant the off-state
    /// couldn't read as red anymore.
    static let danger = Color.red

    /// Muted warm orange — decorative/informational accents like the
    /// "Downloads" link. A different role from `danger` (nothing's wrong),
    /// so it's its own token, not a red variant.
    static let orange = Color(red: 0.85, green: 0.55, blue: 0.15)

    // MARK: Roles
    // These resolve to the same hues as the status pair today, and are
    // deliberately still separate tokens: an inbound transfer isn't a
    // "success", a switch being on isn't one either, and neither is a trusted
    // sender. Sharing `success` between all four meant restyling it would
    // silently repaint the transfer list, every glass switch and the sender
    // shield along with the things that actually report success.

    /// Transfer direction, as a pair — inbound green against outbound blue.
    static let inbound = Color.green
    static let outbound = accent

    /// The two sides of the custom glass switch.
    static let switchOn = Color.green
    static let switchOff = Color.red

    /// A sender the user has chosen to auto-accept.
    static let trusted = Color.green
    /// QR ink: always dark navy on white, independent of app theme — a QR
    /// code needs strong fixed contrast to scan, not a light/dark adaptive
    /// color. Centralized here so it isn't a private literal only QRCodeView
    /// knows about.
    static let qrInk = Color(red: 0.09, green: 0.13, blue: 0.34)

    // MARK: Text color tokens
    // The typography styles below and a handful of one-off "matches style X"
    // spots (PinBadge, badge numbers, the transfer percentage) both read
    // from these — not a hand-copied value that only looks the same. Change
    // one of these and every consumer moves together.
    static let textProminent: Color = .primary     // section/card/body text
    static let textMuted: Color = .secondary       // subtext, badge numbers, percentages
    static let textWindowHeader = Color.primary.opacity(0.9)

    /// Blue lift over the window's material for cards — enough to feel
    /// intentional, well short of the wash that used to drown out the accent
    /// color. Since cards stopped carrying a material of their own (see
    /// `cardSurface`), this is what does most of the work of separating a card
    /// from the window behind it; `cardBorder` only closes the shape.
    static let panelTint = dynamic(
        dark: NSColor(srgbRed: 0.14, green: 0.26, blue: 0.46, alpha: 0.22),
        light: NSColor(srgbRed: 0.55, green: 0.72, blue: 0.95, alpha: 0.28))

    /// Fainter version of the same wash for the whole window.
    static let windowTint = dynamic(
        dark: NSColor(srgbRed: 0.09, green: 0.16, blue: 0.30, alpha: 0.18),
        light: NSColor(srgbRed: 0.65, green: 0.78, blue: 0.95, alpha: 0.14))

    /// The wash a row or segment picks up under the pointer. One value, because
    /// every hoverable surface should react identically — this had been typed
    /// out as `Color.primary.opacity(0.06)` in three separate files.
    static let hoverFill = Color.primary.opacity(0.06)

    /// The recessed track a segmented control's pill slides in.
    static let trackFill = Color.primary.opacity(0.05)

    /// Internal rules: the separator between rows in an `ElementList`, and the
    /// divider inside an expanded transfer. Deliberately not the same token as
    /// `cardBorder` below — one draws *inside* a surface, the other draws its
    /// outline, and tuning the outline for the material-less card design was
    /// silently darkening every row rule along with it.
    ///
    /// This is the value that actually reaches the screen. It used to be read
    /// through a `.opacity(0.3)` at the one call site that mattered, which
    /// meant the number here and the rule you saw were four times apart —
    /// impossible to reason about when tuning.
    static let hairline = dynamic(
        dark: NSColor(white: 1, alpha: 0.08),
        light: NSColor(white: 0, alpha: 0.06))

    /// The outline that separates a card from the window behind it.
    ///
    /// Drawn at 0.5pt — one physical pixel on a Retina display. At 1pt it is
    /// two, which stops reading as an edge and starts reading as a drawn
    /// border. With no material of its own the card leans on `panelTint` for
    /// most of its separation; this only has to close the shape, not define it.
    static let cardBorder = dynamic(
        dark: NSColor(white: 1, alpha: 0.14),
        light: NSColor(white: 0, alpha: 0.10))

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
    }

    // MARK: Radius
    enum Radius {
        static let card: CGFloat = 10
        static let control: CGFloat = 7
    }

    // MARK: Density
    /// How prominent a row is. Service-level rows are `regular`; per-item rows
    /// inside a list (one device, one known sender) read as subordinate and use
    /// `compact`. Row height and switch size come from the same case, so a row
    /// and the control sitting in it can't disagree about which one they are —
    /// this used to be `GlassSwitch.Size`, which meant rows drawing the *system*
    /// switch still sized themselves from a type named after the custom one.
    enum Density {
        case regular, compact

        var rowMinHeight: CGFloat {
            switch self {
            case .regular: return 34
            case .compact: return 26
            }
        }
        var switchSize: CGSize {
            switch self {
            case .regular: return CGSize(width: 34, height: 20)
            case .compact: return CGSize(width: 26, height: 15)
            }
        }
        var knobInset: CGFloat {
            switch self {
            case .regular: return 2
            case .compact: return 1.5
            }
        }
    }

}

// MARK: - Typography

extension Theme {
    /// The type scale — size and weight only, no colour.
    ///
    /// Kept separate from the `*Style()` helpers below because those bind a
    /// size to a colour, and anything needing the same size in a *different*
    /// colour used to bypass them and re-type the number. Five sites had done
    /// exactly that, so the "single source" wasn't one: changing the scale
    /// moved four styles and left the rest behind.
    enum Font {
        /// Group header — most prominent.
        static let section = SwiftUI.Font.system(size: 13, weight: .semibold)
        /// Card headline.
        static let card = SwiftUI.Font.system(size: 12, weight: .semibold)
        /// Body content.
        static let body = SwiftUI.Font.system(size: 11, weight: .regular)
        /// Muted subtext.
        static let caption = SwiftUI.Font.system(size: 10, weight: .regular)
        /// Window title on the traffic-light row.
        static let windowHeader = SwiftUI.Font.system(size: 12, weight: .light)
        /// Small glyph accents — chevrons, badge arrows, direction marks.
        static let glyph = SwiftUI.Font.system(size: 9, weight: .semibold)
    }
}

// Each helper pairs a scale entry with its colour. Where you need one of these
// sizes in another colour, use `Theme.Font.*` directly rather than re-typing it.
extension View {
    /// Group header. Hierarchy comes from size/weight, not colour — section,
    /// card and body text share the same plain text colour on purpose.
    func sectionStyle() -> some View {
        font(Theme.Font.section).foregroundStyle(Theme.textProminent)
    }
    func cardTitle() -> some View {
        font(Theme.Font.card).foregroundStyle(Theme.textProminent)
    }
    func primaryStyle() -> some View {
        font(Theme.Font.body).foregroundStyle(Theme.textProminent)
    }
    func secondaryStyle() -> some View {
        font(Theme.Font.caption).foregroundStyle(Theme.textMuted)
    }
    /// Window title sitting on the traffic-light row ("QShare", "Settings").
    func windowHeaderStyle() -> some View {
        font(Theme.Font.windowHeader).foregroundStyle(Theme.textWindowHeader)
    }
}

// MARK: - Button recipes

extension View {
    /// A borderless button in the app's warm accent.
    ///
    /// Both modifiers are needed, and that is the point of having this in one
    /// place: `.tint` alone only recolours a bordered button's label in dark
    /// appearance — light mode keeps it black regardless — so the label colour
    /// has to be set directly too. That two-line workaround, and the paragraph
    /// explaining it, had been copied into three files.
    func orangeAccent() -> some View {
        tint(Theme.orange).foregroundStyle(Theme.orange)
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
            .cardSurface()
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
                .cardSurface()
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
            // Idempotent: `layout()` runs constantly, and re-assigning these
            // every pass makes AppKit do teardown/setup work for no change.
            // Only touch the scroll view when it has actually drifted back.
            guard sv.hasVerticalScroller || sv.hasHorizontalScroller
                    || sv.drawsBackground || !sv.autohidesScrollers else { return }
            sv.scrollerStyle = .overlay
            sv.autohidesScrollers = true
            sv.hasVerticalScroller = false
            sv.hasHorizontalScroller = false
            sv.drawsBackground = false
        }
    }
}

extension View {
    /// The chrome every top-level surface shares: the window's faint blue wash
    /// over its material, the app tint, the chosen appearance, and no focus
    /// rings. All four surfaces (root, settings, and the two sheets) repeated
    /// these five modifiers by hand — drift in any one of them would only be
    /// visible with two windows open side by side.
    func windowChrome(_ colorScheme: ColorScheme) -> some View {
        self
            // Oversized rather than a plain `.background(Theme.windowTint)`:
            // a background is offered its *content's* bounds, so once the
            // window can be taller than its content the wash stopped short of
            // the top and left a visible seam against the title-bar area.
            // The window clips this to its own edges, so it always covers.
            .background {
                Rectangle().fill(Theme.windowTint)
                    .frame(width: 4000, height: 4000)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            // `.ultraThinMaterial`, not `.regularMaterial`: regular is opaque
            // enough that no desktop reads through, which is the whole point
            // of putting a wash over a material in the first place.
            .containerBackground(.ultraThinMaterial, for: .window)
            .tint(Theme.accent)
            .preferredColorScheme(colorScheme)
            .focusEffectDisabled()          // mouse-only app — no keyboard focus rings
    }

    /// A tinted panel in a continuous rounded rect, with no material of its
    /// own — deliberately.
    ///
    /// A card sits on the window, which already supplies one, so giving the
    /// card a second meant looking through two stacked materials. Materials
    /// compound: two "ultra thin" layers are nowhere near thin, and that —
    /// not the thickness setting — is why the desktop used to stop dead at
    /// the card edge while showing through everywhere around it. One material
    /// for the whole window; a card separates itself with `panelTint` and a
    /// drawn border rather than by hiding what is behind it.
    func cardSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background { shape.fill(Theme.panelTint) }
            .overlay(shape.strokeBorder(Theme.cardBorder, lineWidth: 0.5))
    }
}
