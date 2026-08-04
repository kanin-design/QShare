import SwiftUI

/// Send flow: discover nearby devices → pick one → stage files → send.
/// Or, for a device that isn't listed: stage files → show a QR the device scans.
struct SendView: View {
    @EnvironmentObject private var model: AppModel

    /// Whether this tab is the one actually on screen.
    ///
    /// Both tabs stay mounted so switching between them can't resize the
    /// window (see `RootView`), and SwiftUI does not stop an indefinite
    /// animation in a view it isn't drawing. That matters more than it sounds:
    /// animation in this window is expensive out of proportion to what it
    /// shows, because the window is a translucent material over the desktop
    /// and every animated frame re-blurs it. The idle Send tab measured ~7% of
    /// a core; the same window with nothing animating measures 0.1%. So every
    /// indefinite animation here is gated on actually being visible. Finite
    /// ones need no gate — they run once and stop by themselves.
    private var isActive: Bool { model.mode == .send }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            switch model.connection {
            case .idle:
                discoveryList
            case .staging(let device):
                stagingCard(title: "Send to \(device.name)") { sendButton }
            case .connecting(let device):
                statusCard(text: "Connecting to \(device.name)…", pin: nil)
            case .awaitingConsent(_, let pin):
                statusCard(text: "Waiting for the other device to accept…", pin: pin)
            case .qrStaging:
                stagingCard(title: "Send with QR code") { showQRButton }
            case .qrShowing(let payload):
                qrCard(payload)
            }
        }
    }

    // MARK: Discovery

    private var discoveryList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Nearby devices") {
                // The same mark as the empty state, just small — and only when
                // that one isn't on screen. Two copies of it running at once
                // would be both redundant and needless work.
                if isActive, !model.discoveredDevices.isEmpty {
                    SearchingSymbol(size: CGSize(width: 24, height: 18), isActive: isActive)
                }
            }

            if model.discoveredDevices.isEmpty {
                emptyDiscovery
            } else {
                Card(padding: Theme.Space.xs) {
                    ElementList(items: model.discoveredDevices) { device in
                        DeviceElement(device: device, action: { model.selectDevice(device) },
                                      onDropFiles: { urls in
                                          model.selectDevice(device)
                                          model.stage(urls: urls)
                                      })
                    }
                }
            }

            Card(padding: Theme.Space.xs) {
                ActionElement(
                    icon: "qrcode",
                    title: "Use a QR code",
                    subtitle: "For a device that can't see you over mDNS",
                    action: { model.startQRSend() })
            }
        }
    }

    private var emptyDiscovery: some View {
        VStack(spacing: Theme.Space.sm) {
            SearchingSymbol(isActive: isActive)
            Text("Looking for devices…")
                .cardTitle()
            Text("Open Quick Share on your Android device and set it to be visible.")
                .secondaryStyle()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .cardSurface()
    }

    // MARK: Staging (shared by device-send and QR-send)

    private func stagingCard(title: String,
                             @ViewBuilder primary: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: title) {
                Button("Back") { model.cancelSend() }
                    .buttonStyle(.glass).controlSize(.small).tint(.secondary)
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
        .buttonStyle(.glassProminent)
    }

    private var showQRButton: some View {
        Button(action: { model.showQRCode() }) {
            Label("Show QR code", systemImage: "qrcode").frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.glassProminent)
    }

    private var stagedList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(model.stagedFiles) { file in
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "doc.fill").foregroundStyle(.secondary)
                        Text(file.name).primaryStyle().lineLimit(1)
                        Spacer()
                        Text(file.displaySize).secondaryStyle()
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
                Text("Scan to receive \(sendTitle.lowercased())").cardTitle()
                Text("Open the camera or Quick Share on your Android device and scan this code.")
                    .secondaryStyle()
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: Theme.Space.sm) {
                if isActive { ProgressView().controlSize(.small) }
                Text("Waiting for a device to scan…").secondaryStyle()
            }

            Button("Cancel", role: .cancel) { model.cancelSend() }
                .buttonStyle(.glass).controlSize(.large).tint(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.sm)
    }

    // MARK: Status

    private func statusCard(text: String, pin: String?) -> some View {
        Card {
            VStack(spacing: Theme.Space.md) {
                if pin == nil, isActive { ProgressView() }
                Text(text).cardTitle().multilineTextAlignment(.center)
                if let pin { PinBadge(pin: pin) }
                Button("Cancel", role: .cancel) { model.cancelSend() }
                    .buttonStyle(.glass).controlSize(.large).tint(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sendTitle: String {
        let n = model.stagedFiles.count
        return n == 1 ? "1 file" : "\(n) files"
    }
}
