import SwiftUI

/// App shell: header, Send/Receive switch, the active flow, and a shared list of
/// active transfers. Incoming requests are presented as a global sheet so they
/// surface regardless of the active tab.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                modePicker

                Group {
                    switch model.mode {
                    case .send:    SendView()
                    case .receive: ReceiveView()
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.mode)

                if !model.transfers.isEmpty {
                    transfersSection
                }
            }
            .padding(Theme.Space.lg)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(.regularMaterial, for: .window)
        .tint(Theme.accent)
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

    // Slim title on the traffic-light row: a hint of white, 100% centered, no divider.
    private var header: some View {
        Text("QShare")
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(.primary.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.top, 9)
            .padding(.bottom, 7)
    }

    private var modePicker: some View {
        ModeToggle(selection: $model.mode)
    }

    private var transfersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Transfers", trailing: AnyView(
                Button("Clear") { model.clearFinishedTransfers() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            ))
            ForEach(model.transfers) { transfer in
                TransferRow(transfer: transfer) { model.cancel(transfer) }
            }
        }
    }
}

/// Custom Send/Receive control: a rounded track with a smooth sliding glass pill
/// under the selected segment (Liquid-Glass material, spring-animated).
struct ModeToggle: View {
    @Binding var selection: AppMode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppMode.allCases) { mode in
                let isOn = selection == mode
                Text(mode.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isOn {
                            Capsule(style: .continuous)
                                .fill(.regularMaterial)
                                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            selection = mode
                        }
                    }
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous).fill(Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
