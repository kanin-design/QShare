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

/// Send/Receive switch: two segments with a single Apple Liquid-Glass pill that
/// morphs across to the selected one (GlassEffectContainer + glassEffectID).
struct ModeToggle: View {
    @Binding var selection: AppMode
    @Namespace private var glass
    @State private var hovered: AppMode?

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(AppMode.allCases) { mode in
                    segment(mode)
                }
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous).fill(Color.primary.opacity(0.05))
        )
    }

    @ViewBuilder
    private func segment(_ mode: AppMode) -> some View {
        let isOn = selection == mode
        let isHover = hovered == mode && !isOn

        let label = Text(mode.rawValue)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn || isHover ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Capsule(style: .continuous))

        Group {
            if isOn {
                // The real Liquid-Glass pill — morphs to whichever segment is on.
                label.glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                    .glassEffectID("pill", in: glass)
            } else {
                label.background {
                    if isHover { Capsule(style: .continuous).fill(Color.primary.opacity(0.06)) }
                }
            }
        }
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) {
                if inside { hovered = mode } else if hovered == mode { hovered = nil }
            }
        }
        .onTapGesture {
            withAnimation(.smooth(duration: 0.32)) { selection = mode }
        }
    }
}
