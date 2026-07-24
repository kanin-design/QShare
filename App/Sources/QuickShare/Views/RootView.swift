import SwiftUI
import AppKit

/// App shell: header, Send/Receive switch, the active flow, and a shared list of
/// active transfers. Incoming requests are presented as a global sheet so they
/// surface regardless of the active tab.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            modePicker
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.lg)
                .padding(.bottom, Theme.Space.lg)

            // Fixed controls (send/receive)…
            Group {
                switch model.mode {
                case .send:    SendView()
                case .receive: ReceiveView()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.mode)
            .padding(.horizontal, Theme.Space.lg)

            // …then the transfers history fills the rest and scrolls on its own.
            if !model.transfers.isEmpty {
                TransfersList(transfers: model.transfers,
                              onClear: { model.clearFinishedTransfers() },
                              onCancel: { model.cancel($0) })
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.top, Theme.Space.lg)
                    .padding(.bottom, Theme.Space.lg)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)   // let the wordmark sit on the traffic-light row
        .background(Theme.windowTint)               // intentional blue wash over the material
        .containerBackground(.regularMaterial, for: .window)
        .tint(Theme.accent)
        .preferredColorScheme(model.appearance.colorScheme)
        .focusEffectDisabled()          // mouse-only app — no keyboard focus rings
        .animation(.easeInOut(duration: 0.2), value: model.connection)
        .sheet(isPresented: incomingBinding) {
            if let req = model.incomingRequest {
                IncomingRequestSheet(
                    request: req,
                    onAccept: { trust in model.respondToIncoming(accept: true, trustDevice: trust) },
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

    // Slim title on the traffic-light row: 100% centered, vertically aligned with
    // the traffic-light buttons (28pt band), no divider.
    private var header: some View {
        Text("QShare")
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(.primary.opacity(0.9))
            .frame(maxWidth: .infinity, minHeight: 28)
    }

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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn || isHover ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
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
