import SwiftUI
import AppKit

/// Scroll geometry we track to drive the custom scrollbar.
private struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var container: CGFloat = 0
}

/// Natural height of the rows, measured independently of the scroll viewport so
/// the panel can size itself to its content (and only scroll past a cap).
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The transfers history: ONE glass panel (squircle) divided by hairlines into
/// chronological (newest-first) rows. The panel grows with the number of
/// transfers and only starts scrolling — with a custom liquid-glass scrollbar —
/// once it would exceed the space available below the controls.
struct TransfersList: View {
    let transfers: [ActiveTransfer]
    let onClear: () -> Void
    let onCancel: (ActiveTransfer) -> Void

    @State private var metrics = ScrollMetrics()
    @State private var scrollPos = ScrollPosition(edge: .top)
    @State private var contentHeight: CGFloat = 0

    private var scrollable: Bool { metrics.content - metrics.container > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Transfers", trailing: AnyView(
                Button("Clear", action: onClear)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
            ))

            GeometryReader { geo in
                // Fit content when it's short; cap at the available height and scroll otherwise.
                let panelH = contentHeight <= 0 ? geo.size.height : min(contentHeight, geo.size.height)

                ScrollView {
                    // Same construction as the nearby-devices list: hover-highlighting
                    // rows on one glass panel, separated by a 2pt gap (no divider lines).
                    VStack(spacing: 2) {
                        ForEach(transfers) { t in
                            TransferRow(transfer: t) { onCancel(t) }
                        }
                    }
                    .padding(Theme.Space.xs)
                    .padding(.trailing, scrollable ? 12 : 0)   // clear the scrollbar
                    .background(ScrollerHider())   // suppress native scroller + its background
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                    })
                }
                .frame(height: panelH)
                .scrollPosition($scrollPos)
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                    ScrollMetrics(offset: geo.contentOffset.y,
                                  content: geo.contentSize.height,
                                  container: geo.containerSize.height)
                } action: { _, new in metrics = new }
                .glassSurface(radius: Theme.Radius.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(alignment: .trailing) {
                    if scrollable {
                        GlassScrollbar(offset: metrics.offset,
                                       content: metrics.content,
                                       container: metrics.container) { y in
                            scrollPos.scrollTo(y: y)
                        }
                        .frame(height: panelH)
                        .padding(.trailing, 3)
                    }
                }
            }
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        }
    }
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
