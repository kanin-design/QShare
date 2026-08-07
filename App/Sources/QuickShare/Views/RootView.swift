import SwiftUI
import AppKit

/// App shell: header, Send/Receive switch, the active flow, and a shared list of
/// active transfers. Incoming requests are presented as a global sheet so they
/// surface regardless of the active tab.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // `@Bindable` is what produces `$model` under Observation — the
        // `@Environment` property itself is not a binding source.
        @Bindable var model = model
        return VStack(spacing: 0) {
            header
            // Inline rather than a computed property: `@Bindable` is scoped to
            // `body`, so `$model` isn't visible from one.
            ModeToggle(selection: $model.mode)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.lg)
                .padding(.bottom, Theme.Space.lg)

            // Both tabs stay mounted, only the active one visible and
            // hit-testable, so the stack's height is the taller of the two and
            // doesn't change with the selection. Switching between them used
            // to resize the whole window — tabs shouldn't do that. `.top`
            // matters: a ZStack centres by default, which would float the
            // shorter tab in the middle of the taller one's height.
            ZStack(alignment: .top) {
                SendView()
                    .opacity(model.mode == .send ? 1 : 0)
                    .allowsHitTesting(model.mode == .send)
                    .accessibilityHidden(model.mode != .send)
                ReceiveView()
                    .opacity(model.mode == .receive ? 1 : 0)
                    .allowsHitTesting(model.mode == .receive)
                    .accessibilityHidden(model.mode != .receive)
            }
            .animation(.easeInOut(duration: 0.2), value: model.mode)
            .padding(.horizontal, Theme.Space.lg)

            // The transfers history caps itself and scrolls past that, rather
            // than being sized from "whatever is left in the window" — that
            // needed a root GeometryReader, which left the window's ideal
            // height undefined and defeated `.windowResizability(.contentSize)`.
            if !model.transfers.isEmpty {
                TransfersList(transfers: model.transfers,
                              onClear: { model.clearFinishedTransfers() },
                              onCancel: { model.cancel($0) })
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.top, Theme.Space.lg)
                    .padding(.bottom, Theme.Space.lg)
            }
        }
        // No `maxHeight: .infinity`: that stretches the content to the window
        // instead of letting the window take its height from the content.
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)   // let the wordmark sit on the traffic-light row
        .windowChrome(model.effectiveColorScheme)
        .animation(.easeInOut(duration: 0.2), value: model.connection)
        // ⌘⌥I — which build am I running? Driven by the menu command so the
        // shortcut works wherever focus happens to be.
        .sheet(isPresented: $model.showingBuildInfo) {
            DebugInfoSheet { model.showingBuildInfo = false }
        }
        .sheet(isPresented: incomingBinding) {
            if let req = model.incomingRequest {
                IncomingRequestSheet(
                    request: req,
                    isKnown: model.isKnown(req.device.name),
                    onAccept: { always in
                        model.respondToIncoming(accept: true, alwaysAccept: always)
                    },
                    onDecline: { model.respondToIncoming(accept: false) })
            }
        }
    }

    /// Presents the incoming sheet; dismissing it (Esc) counts as declining.
    private var incomingBinding: Binding<Bool> {
        Binding(
            get: { model.incomingRequest != nil },
            set: { presented in
                if !presented, model.incomingRequest != nil {
                    model.respondToIncoming(accept: false)
                }
            })
    }

    private var header: some View { WindowHeader(title: "QShare") }

}

/// Send/Receive switch: a single Apple Liquid-Glass pill that physically slides
/// under the selected segment and springs into place like a magnet snap.
struct ModeToggle: View {
    @Binding var selection: AppMode
    @State private var hovered: AppMode?
    /// Where the pill's leading edge is while a drag is in progress, in points
    /// from the left. Nil when it is resting on the selected segment.
    @State private var dragX: CGFloat?

    private static let modes = AppMode.allCases
    private static let spacing: CGFloat = 6
    /// Inset between the track's outer capsule and the segments.
    ///
    /// Named because two things depend on it and they are far apart: the
    /// `.padding` below, and the drag maths, which must subtract it to convert
    /// a pointer position into a pill position. As two bare `4`s, changing the
    /// padding silently stopped the pill tracking the pointer, with nothing in
    /// the code connecting the two.
    private static let trackInset: CGFloat = 4

    var body: some View {
        // Deliberately *not* wrapped in a `GlassEffectContainer`. A container
        // groups its content for glass sampling, which pulls the labels into
        // what the pill refracts — the selected word then renders with mirrored,
        // blurred copies above and below it. A container earns its place when
        // several glass shapes need to blend or morph into one another; with a
        // single pill it only causes that.
        Group {
            HStack(spacing: Self.spacing) {
                ForEach(Self.modes) { mode in
                    segment(mode)
                }
            }
            // Behind the labels, not over them.
            //
            // Over them, `glassEffect` renders the word with mirrored, blurred
            // copies above and below it. That was tested with and without a
            // `GlassEffectContainer` and it happens either way: the effect's
            // refraction *includes* blur, and there is no option separating the
            // two. It looks right in Apple's own material because it sits over
            // photographs, where a soft mirrored highlight reads as a
            // reflection; over a 12pt label it reads as broken text.
            //
            // Crisp bending without blur is a different API — `distortionEffect`
            // with a Metal shader, which displaces samples geometrically rather
            // than compositing a blurred copy.
            .background(alignment: .leading) { pill }
            // Measure the track itself, rather than inferring it from one
            // segment's width times the count — that assumed equal segments and
            // silently drifted if they were ever not.
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { trackWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, new in trackWidth = new }
                }
            }
        }
        .padding(Self.trackInset)
        .background(Capsule(style: .continuous).fill(Theme.trackFill))
        // Drag anywhere on the track to slide the pill. Simultaneous and with a
        // minimum distance, so a plain click still reaches the segment's own tap
        // underneath and only real movement starts a drag.
        .simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .local)
                .onChanged { value in
                    guard trackWidth > 0 else { return }
                    let width = segmentWidth(in: trackWidth)
                    let step = width + Self.spacing
                    // Centre the pill on the pointer, allowing for the track
                    // inset between the gesture's space and the segments.
                    let proposed = value.location.x - Self.trackInset - width / 2
                    let x = min(max(proposed, 0), step * CGFloat(Self.modes.count - 1))
                    dragX = x
                    let nearest = Int((x / step).rounded())
                    let mode = Self.modes[min(max(nearest, 0), Self.modes.count - 1)]
                    if mode != selection { selection = mode }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.68)) {
                        dragX = nil
                    }
                }
        )

    }

    private var pill: some View {
        GeometryReader { geo in
            let x = dragX ?? restingX(in: geo.size.width)
            Capsule(style: .continuous)
                .fill(.clear)
                // `.clear`, not `.regular`. `.regular` is the adaptive *frosted*
                // material — it blurs and lightens whatever is behind it, which
                // is what made this read as a milky blob rather than glass.
                // `.clear` is transparent: the window shows through it cleanly
                // and the lensing stays at the rim, where it belongs.
                .glassEffect(.clear.interactive(), in: Capsule(style: .continuous))
                .frame(width: segmentWidth(in: geo.size.width), height: geo.size.height)
                .offset(x: x)
                // Only animate the resting position; while dragging the pill
                // should track the pointer exactly, with no easing behind it.
                .animation(dragX == nil ? .spring(response: 0.3, dampingFraction: 0.68) : nil,
                           value: x)
                // Decoration only. The pill cannot take the drag itself: it
                // sits behind the labels, so they intercept every press before
                // it arrives. That also puts `.interactive()`'s press response
                // out of reach — the stretch and rim fringing a real Liquid
                // Glass control shows when held needs the glass to *be* the
                // thing pressed, which is true of a switch knob with nothing
                // over it, and false of anything sitting under a label.
                .allowsHitTesting(false)
        }
    }

    /// Width of the whole track, measured from the segments.
    @State private var trackWidth: CGFloat = 0

    private func segmentWidth(in total: CGFloat) -> CGFloat {
        let count = CGFloat(Self.modes.count)
        return (total - Self.spacing * (count - 1)) / count
    }

    private func restingX(in total: CGFloat) -> CGFloat {
        let index = CGFloat(Self.modes.firstIndex(of: selection) ?? 0)
        return index * (segmentWidth(in: total) + Self.spacing)
    }

    private func segment(_ mode: AppMode) -> some View {
        let isOn = selection == mode
        let isHover = hovered == mode && !isOn

        return Text(mode.rawValue)
            .font(Theme.Font.card)
            .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            // Hover shows a faint fill (like the list rows), not a color change.
            .background {
                if isHover {
                    Capsule(style: .continuous).fill(Theme.hoverFill)
                }
            }
            .contentShape(Capsule(style: .continuous))
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) {
                    if inside { hovered = mode } else if hovered == mode { hovered = nil }
                }
            }
            .onTapGesture {
                // Snappy spring with a touch of overshoot — the "magnet" settle.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.68)) { selection = mode }
            }
    }
}
