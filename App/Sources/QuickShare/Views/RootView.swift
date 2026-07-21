import SwiftUI

/// App shell: header, Send/Receive switch, the active flow, and a shared list of
/// active transfers. Incoming requests are presented as a global sheet so they
/// surface regardless of the active tab.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

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

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            BrandMark()
            VStack(alignment: .leading, spacing: 0) {
                Text("QShare").font(.title2.weight(.semibold))
                Text("Share with nearby Android devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.xl)      // clear the window traffic-light buttons
        .padding(.bottom, Theme.Space.md)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $model.mode) {
            ForEach(AppMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
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
