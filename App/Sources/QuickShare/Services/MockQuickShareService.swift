import Foundation

/// Fake engine that drives the dummy UI through every state with realistic
/// timing, so the interface can be reviewed before the real protocol lands.
///
/// Nothing here touches the network. Replace with the NearDrop-backed
/// implementation and delete this file.
@MainActor
final class MockQuickShareService: QuickShareService {
    weak var delegate: QuickShareServiceDelegate?

    private var advertising = false
    private var discovering = false

    private let sampleDevices = [
        RemoteDevice(id: "dev-pixel", name: "Pixel 8 Pro", type: .phone),
        RemoteDevice(id: "dev-galaxy", name: "Galaxy S24", type: .phone),
        RemoteDevice(id: "dev-tab", name: "Galaxy Tab S9", type: .tablet),
    ]

    // MARK: Receive side

    func startAdvertising(deviceName: String) {
        advertising = true
        delegate?.serviceDidUpdateVisibility(isVisible: true)

        // Simulate an Android device sending us something ~6s after we go visible.
        schedule(6.0) { [weak self] in
            guard let self, self.advertising else { return }
            let req = IncomingRequest(
                id: "in-\(UUID().uuidString.prefix(6))",
                device: RemoteDevice(id: "dev-pixel", name: "Pixel 8 Pro", type: .phone),
                fileNames: ["sunset.jpg"],
                totalBytes: 2_412_000,
                pin: Self.randomPin()
            )
            self.delegate?.serviceDidReceiveIncomingRequest(req)
        }
    }

    func stopAdvertising() {
        advertising = false
        delegate?.serviceDidUpdateVisibility(isVisible: false)
    }

    func respondToIncoming(id: String, accept: Bool) {
        guard accept else {
            delegate?.serviceDidFinishTransfer(id: id, error: nil)   // declined = clean close
            return
        }
        delegate?.serviceDidAcceptTransfer(id: id)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let resolved = [TransferFile(name: "sunset.jpg", url: downloads?.appendingPathComponent("sunset.jpg"))]
        simulateProgress(id: id, resolve: resolved)
    }

    // MARK: Send side

    func startDiscovery() {
        discovering = true
        // Devices trickle in like real mDNS discovery.
        for (i, device) in sampleDevices.enumerated() {
            schedule(0.8 + Double(i) * 0.9) { [weak self] in
                guard let self, self.discovering else { return }
                self.delegate?.serviceDidDiscover(device)
            }
        }
    }

    func stopDiscovery() {
        discovering = false
    }

    func sendFiles(_ files: [FileItem], to device: RemoteDevice) {
        let id = device.id   // matches the real engine, which keys by device id
        // Handshake completes → PIN, then the remote user accepts, then bytes flow.
        schedule(1.2) { [weak self] in
            self?.delegate?.serviceDidEstablishConnection(with: device, pin: Self.randomPin())
            self?.schedule(1.8) {
                self?.delegate?.serviceDidAcceptTransfer(id: id)
                self?.simulateProgress(id: id)
            }
        }
    }

    func cancelTransfer(id: String) {
        cancelled.insert(id)
    }

    // MARK: QR send

    private var qrActive = false

    func prepareQRCode() -> String? {
        qrActive = true
        // Pretend a device scans it ~4s later and becomes reachable.
        schedule(4.0) { [weak self] in
            guard let self, self.qrActive else { return }
            self.delegate?.serviceDidMatchQRDevice(
                RemoteDevice(id: "dev-pixel", name: "Pixel 8 Pro", type: .phone))
        }
        return "https://quickshare.google/qrcode#key=MOCK-\(UUID().uuidString.prefix(8))"
    }

    func cancelQRCode() {
        qrActive = false
    }

    // MARK: Simulation helpers

    private var cancelled = Set<String>()

    private func simulateProgress(id: String, step: Double = 0.06, resolve: [TransferFile]? = nil) {
        func tick(_ fraction: Double) {
            guard !cancelled.contains(id) else {
                delegate?.serviceDidFinishTransfer(id: id, error: "Cancelled")
                return
            }
            if fraction >= 1.0 {
                delegate?.serviceDidUpdateProgress(id: id, fraction: 1.0)
                if let resolve { delegate?.serviceDidResolveFiles(id: id, files: resolve) }
                delegate?.serviceDidFinishTransfer(id: id, error: nil)
                return
            }
            delegate?.serviceDidUpdateProgress(id: id, fraction: fraction)
            schedule(0.12) { tick(fraction + step) }
        }
        tick(0)
    }

    private func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func randomPin() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }
}
