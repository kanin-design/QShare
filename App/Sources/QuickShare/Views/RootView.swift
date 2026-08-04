import SwiftUI
import AppKit

/// App shell: header, Send/Receive switch, the active flow, and a shared list of
/// active transfers. Incoming requests are presented as a global sheet so they
/// surface regardless of the active tab.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    /// Height of the fixed controls, measured rather than assumed.
    @State private var controlsHeight: CGFloat = 0

    /// Room left for the transfers panel: the window minus the controls and the
    /// padding around the panel, with a floor so it stays usable when the window
    /// is dragged very short.
    private func transfersMaxHeight(in windowHeight: CGFloat) -> CGFloat {
        let verticalPadding = Theme.Space.lg * 2
        return max(120, windowHeight - controlsHeight - verticalPadding)
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Fixed controls (header, mode switch, send/receive), measured so
                // the transfers panel below knows how much room is genuinely left.
                VStack(spacing: 0) {
                    header
                    modePicker
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.top, Theme.Space.lg)
                        .padding(.bottom, Theme.Space.lg)

                    Group {
                        switch model.mode {
                        case .send:    SendView()
                        case .receive: ReceiveView()
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: model.mode)
                    .padding(.horizontal, Theme.Space.lg)
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: ControlsHeightKey.self, value: g.size.height)
                })

                // …then the transfers history wraps its rows, growing only until
                // it would run out of window, at which point it scrolls.
                if !model.transfers.isEmpty {
                    TransfersList(transfers: model.transfers,
                                  onClear: { model.clearFinishedTransfers() },
                                  onCancel: { model.cancel($0) },
                                  maxHeight: transfersMaxHeight(in: geo.size.height))
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.top, Theme.Space.lg)
                        .padding(.bottom, Theme.Space.lg)
                }

                Spacer(minLength: 0)
            }
            .onPreferenceChange(ControlsHeightKey.self) { controlsHeight = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var modePicker: some View {
        ModeToggle(selection: $model.mode)
    }

}

/// Send/Receive switch: a single Apple Liquid-Glass pill that physically slides
/// under the selected segment and springs into place like a magnet snap.
struct ModeToggle: View {
    @Binding var selection: AppMode
    @State private var hovered: AppMode?

    private static let modes = AppMode.allCases
    private static let spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Self.modes) { mode in
                segment(mode)
            }
        }
        // A single glass pill in the background, slid to the selected segment.
        .background(alignment: .leading) {
            GeometryReader { geo in
                let n = CGFloat(Self.modes.count)
                let w = (geo.size.width - Self.spacing * (n - 1)) / n
                let idx = CGFloat(Self.modes.firstIndex(of: selection) ?? 0)
                Capsule(style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                    .frame(width: w, height: geo.size.height)
                    .offset(x: idx * (w + Self.spacing))
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func segment(_ mode: AppMode) -> some View {
        let isOn = selection == mode
        let isHover = hovered == mode && !isOn

        return Text(mode.rawValue)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            // Hover shows a faint fill (like the list rows), not a color change.
            .background {
                if isHover {
                    Capsule(style: .continuous).fill(Color.primary.opacity(0.06))
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
