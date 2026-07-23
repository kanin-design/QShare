import SwiftUI
import AppKit

/// Scroll geometry we track to drive the custom scrollbar.
private struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var container: CGFloat = 0
}

/// The transfers history: one chronological (newest-first) scrollable list with a
/// custom liquid-glass scrollbar. Header + Clear stay fixed; only the rows scroll.
struct TransfersList: View {
    let transfers: [ActiveTransfer]
    let onClear: () -> Void
    let onCancel: (ActiveTransfer) -> Void

    @State private var metrics = ScrollMetrics()
    @State private var scrollPos = ScrollPosition(edge: .top)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Transfers", trailing: AnyView(
                Button("Clear", action: onClear)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
            ))

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(transfers) { t in
                        TransferRow(transfer: t) { onCancel(t) }
                    }
                }
                .padding(.trailing, 12)   // clearance for the scrollbar
                .background(ScrollerHider())   // suppress the native (legacy) scrollbar
            }
            .scrollPosition($scrollPos)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                ScrollMetrics(offset: geo.contentOffset.y,
                              content: geo.contentSize.height,
                              container: geo.containerSize.height)
            } action: { _, new in metrics = new }
            .overlay(alignment: .trailing) {
                GlassScrollbar(offset: metrics.offset,
                               content: metrics.content,
                               container: metrics.container) { y in
                    scrollPos.scrollTo(y: y)
                }
            }
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
            let trackH = geo.size.height
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
        }
        .frame(width: 12)
        .opacity(scrollable > 1 ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: scrollable > 1)
    }
}

/// Forces the enclosing NSScrollView to overlay/auto-hide (and hide) its native
/// scrollers, so no legacy scrollbar shows even on "always show scroll bars".
struct ScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.configure(v) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(v) }
    }
    private static func configure(_ v: NSView) {
        guard let sv = v.enclosingScrollView else { return }
        sv.scrollerStyle = .overlay
        sv.autohidesScrollers = true
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
    }
}
