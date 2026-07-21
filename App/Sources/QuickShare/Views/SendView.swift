import SwiftUI

/// Send flow: discover nearby devices → pick one → stage files → send.
/// Or, for a device that isn't listed: stage files → show a QR the device scans.
struct SendView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            switch model.connection {
            case .idle:
                discoveryList
            case .staging(let device):
                stagingCard(title: "Send to \(device.name)", icon: device.type.symbol) { sendButton }
            case .connecting(let device):
                statusCard(text: "Connecting to \(device.name)…", pin: nil)
            case .awaitingConsent(_, let pin):
                statusCard(text: "Waiting for the other device to accept…", pin: pin)
            case .qrStaging:
                stagingCard(title: "Send with QR code", icon: "qrcode") { showQRButton }
            case .qrShowing(let payload):
                qrCard(payload)
            }
        }
        .onAppear { model.startDiscovery() }
        .onDisappear { model.stopDiscovery() }
    }

    // MARK: Discovery

    private var discoveryList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Nearby devices", trailing: AnyView(
                ProgressView().controlSize(.small)
            ))

            if model.discoveredDevices.isEmpty {
                emptyDiscovery
            } else {
                VStack(spacing: 2) {
                    ForEach(model.discoveredDevices) { device in
                        DeviceRow(device: device, action: { model.selectDevice(device) },
                                  onDropFiles: { urls in
                                      model.selectDevice(device)
                                      model.stage(urls: urls)
                                  })
                    }
                }
                .padding(Theme.Space.xs)
                .glassSurface()
            }

            Button {
                model.startQRSend()
            } label: {
                Label("Don’t see your device? Use a QR code", systemImage: "qrcode")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .tint(.secondary)
            .focusEffectDisabled()      // no stray focus ring
            .padding(.top, Theme.Space.xs)
        }
    }

    private var emptyDiscovery: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("Looking for devices…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Open Quick Share on your Android device and set it to be visible.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .glassSurface()
    }

    // MARK: Staging (shared by device-send and QR-send)

    private func stagingCard(title: String, icon: String,
                             @ViewBuilder primary: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Image(systemName: icon).foregroundStyle(Theme.accent)
                Text(title).font(.headline)
                Spacer()
                Button("Back") { model.cancelSend() }.controlSize(.small)
            }

            DropZoneView { urls in model.stage(urls: urls) }

            if !model.stagedFiles.isEmpty {
                stagedList
                primary()
            }
        }
    }

    private var sendButton: some View {
        Button(action: { model.sendStagedFiles() }) {
            Label("Send \(sendTitle)", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }

    private var showQRButton: some View {
        Button(action: { model.showQRCode() }) {
            Label("Show QR code", systemImage: "qrcode").frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }

    private var stagedList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(model.stagedFiles) { file in
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "doc.fill").foregroundStyle(.secondary)
                        Text(file.name).font(.callout).lineLimit(1)
                        Spacer()
                        Text(file.displaySize).font(.caption).foregroundStyle(.secondary)
                        Button {
                            model.removeStaged(file)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, 6)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 150)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: QR display (waiting for a scan)

    private func qrCard(_ payload: String) -> some View {
        VStack(spacing: Theme.Space.lg) {
            QRCodeView(payload: payload)

            VStack(spacing: 4) {
                Text("Scan to receive \(sendTitle.lowercased())").font(.headline)
                Text("Open the camera or Quick Share on your Android device and scan this code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: Theme.Space.sm) {
                ProgressView().controlSize(.small)
                Text("Waiting for a device to scan…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Cancel", role: .cancel) { model.cancelSend() }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.sm)
    }

    // MARK: Status

    private func statusCard(text: String, pin: String?) -> some View {
        Card {
            VStack(spacing: Theme.Space.md) {
                if pin == nil { ProgressView() }
                Text(text).font(.headline).multilineTextAlignment(.center)
                if let pin { PinBadge(pin: pin) }
                Button("Cancel", role: .cancel) { model.cancelSend() }
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sendTitle: String {
        let n = model.stagedFiles.count
        return n == 1 ? "1 file" : "\(n) files"
    }
}
