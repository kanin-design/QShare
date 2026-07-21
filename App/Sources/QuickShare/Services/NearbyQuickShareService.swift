import Foundation
import NearbyShareKit

/// Real Quick Share engine: wraps NearbyShareKit's `NearbyConnectionManager`
/// (vendored from NearDrop) and translates its two delegate protocols
/// (`MainAppDelegate` for receiving, `ShareExtensionDelegate` for discovery)
/// into our `QuickShareServiceDelegate`.
///
/// The type stays nonisolated (it conforms to NearbyShareKit's nonisolated
/// delegate protocols); `QuickShareService` conformance is declared in an
/// extension so the class isn't force-inferred onto the main actor. Every UI
/// callback is hopped onto the main actor via `emit`.
final class NearbyQuickShareService: NSObject {
    weak var delegate: QuickShareServiceDelegate?

    private let manager = NearbyConnectionManager.shared

    /// Retain per-transfer outbound delegates, keyed by device id.
    private var outboundHandles: [String: OutboundHandle] = [:]

    /// Hop an engine callback onto the main actor for the UI.
    func emit(_ body: @escaping @MainActor () -> Void) {
        Task { @MainActor in body() }
    }

    /// Reach the delegate on the main actor (used by OutboundHandle).
    func emitToDelegate(_ body: @escaping @MainActor (QuickShareServiceDelegate) -> Void) {
        emit { if let d = self.delegate { body(d) } }
    }

    func finishedOutbound(_ id: String) {
        emit { self.outboundHandles.removeValue(forKey: id) }
    }
}

// MARK: - QuickShareService (in an extension to avoid @MainActor inference)

extension NearbyQuickShareService: QuickShareService {

    // Receive side
    func startAdvertising(deviceName: String) {
        manager.mainAppDelegate = self
        manager.becomeVisible()
        emit { self.delegate?.serviceDidUpdateVisibility(isVisible: true) }
    }

    func stopAdvertising() {
        manager.becomeInvisible()
        emit { self.delegate?.serviceDidUpdateVisibility(isVisible: false) }
    }

    func respondToIncoming(id: String, accept: Bool) {
        manager.submitUserConsent(transferID: id, accept: accept)
    }

    // Send side
    func startDiscovery() {
        manager.startDeviceDiscovery()
        manager.addShareExtensionDelegate(self)
    }

    func stopDiscovery() {
        manager.removeShareExtensionDelegate(self)
        manager.stopDeviceDiscovery()
    }

    func sendFiles(_ files: [FileItem], to device: RemoteDevice) {
        let handle = OutboundHandle(transferID: device.id, device: device, owner: self)
        outboundHandles[device.id] = handle
        manager.startOutgoingTransfer(deviceID: device.id, delegate: handle, urls: files.map(\.url))
    }

    func cancelTransfer(id: String) {
        manager.cancelOutgoingTransfer(id: id)
        outboundHandles.removeValue(forKey: id)
    }

    // QR send
    func prepareQRCode() -> String? {
        // Same key exchange Android uses: an EC key whose advertising token we
        // watch for while browsing. The QR is the Quick Share App Link URL —
        // Android only routes it to Quick Share in exactly this form.
        let key = manager.generateQrCodeKey()
        return "https://quickshare.google/qrcode#key=\(key)"
    }

    func cancelQRCode() {
        manager.clearQrCodeKey()
    }
}

// MARK: - Receive callbacks (MainAppDelegate)

extension NearbyQuickShareService: MainAppDelegate {
    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
        let names = transfer.files.isEmpty
            ? [transfer.textDescription ?? "Link"]
            : transfer.files.map(\.name)
        let total = transfer.files.reduce(Int64(0)) { $0 + $1.size }
        let request = IncomingRequest(
            id: transfer.id,
            device: mapDevice(device),
            fileNames: names,
            totalBytes: total,
            pin: transfer.pinCode ?? "----")
        emit { self.delegate?.serviceDidReceiveIncomingRequest(request) }
    }

    func incomingTransfer(id: String, progress: Double) {
        emit { self.delegate?.serviceDidUpdateProgress(id: id, fraction: progress) }
    }

    func incomingTransfer(id: String, savedFiles: [URL]) {
        let files = savedFiles.map { TransferFile(name: $0.lastPathComponent, url: $0) }
        emit { self.delegate?.serviceDidResolveFiles(id: id, files: files) }
    }

    func incomingTransfer(id: String, didFinishWith error: Error?) {
        let message = error.map(userMessage(for:))
        emit { self.delegate?.serviceDidFinishTransfer(id: id, error: message) }
    }
}

// MARK: - Discovery callbacks (ShareExtensionDelegate)

extension NearbyQuickShareService: ShareExtensionDelegate {
    func addDevice(device: RemoteDeviceInfo) {
        let mapped = mapDevice(device)
        emit { self.delegate?.serviceDidDiscover(mapped) }
    }

    func removeDevice(id: String) {
        emit { self.delegate?.serviceDidLose(deviceID: id) }
    }

    // A device scanned our QR and is now reachable — tell the app to send.
    func startTransferWithQrCode(device: RemoteDeviceInfo) {
        let mapped = mapDevice(device)
        emit { self.delegate?.serviceDidMatchQRDevice(mapped) }
    }

    // Remaining per-transfer callbacks are routed via OutboundHandle, not here.
    func connectionWasEstablished(pinCode: String) {}
    func connectionFailed(with error: Error) {}
    func transferAccepted() {}
    func transferProgress(progress: Double) {}
    func transferFinished() {}
}

// MARK: - Per-transfer outbound delegate

/// One instance per outgoing transfer. Carries the transfer id + device so the
/// idless NearDrop callbacks can be routed back with full context.
private final class OutboundHandle: ShareExtensionDelegate {
    let transferID: String
    let device: RemoteDevice
    weak var owner: NearbyQuickShareService?

    init(transferID: String, device: RemoteDevice, owner: NearbyQuickShareService) {
        self.transferID = transferID
        self.device = device
        self.owner = owner
    }

    // Discovery methods are no-ops here.
    func addDevice(device: RemoteDeviceInfo) {}
    func removeDevice(id: String) {}
    func startTransferWithQrCode(device: RemoteDeviceInfo) {}

    func connectionWasEstablished(pinCode: String) {
        let device = device
        owner?.emitToDelegate { $0.serviceDidEstablishConnection(with: device, pin: pinCode) }
    }

    func transferAccepted() {
        let id = transferID
        owner?.emitToDelegate { $0.serviceDidAcceptTransfer(id: id) }
    }

    func transferProgress(progress: Double) {
        let id = transferID
        owner?.emitToDelegate { $0.serviceDidUpdateProgress(id: id, fraction: progress) }
    }

    func connectionFailed(with error: Error) {
        let id = transferID
        let device = device
        let message = userMessage(for: error)
        owner?.emitToDelegate {
            $0.serviceDidFailConnection(with: device, error: message)
            $0.serviceDidFinishTransfer(id: id, error: message)
        }
        owner?.finishedOutbound(id)
    }

    func transferFinished() {
        let id = transferID
        owner?.emitToDelegate { $0.serviceDidFinishTransfer(id: id, error: nil) }
        owner?.finishedOutbound(id)
    }
}

// MARK: - Mapping helpers (free functions, so `DeviceType` resolves to ours)

private func mapDevice(_ info: RemoteDeviceInfo) -> RemoteDevice {
    let type: DeviceType
    switch info.type {
    case .phone:    type = .phone
    case .tablet:   type = .tablet
    case .computer: type = .computer
    case .unknown:  type = .unknown
    }
    return RemoteDevice(id: info.id ?? UUID().uuidString, name: info.name, type: type)
}

private func userMessage(for error: Error) -> String {
    if let e = error as? NearbyError {
        switch e {
        case .canceled(let reason):
            switch reason {
            case .userRejected:    return "Declined"
            case .userCanceled:    return "Cancelled"
            case .notEnoughSpace:  return "Not enough space"
            case .unsupportedType: return "Unsupported file type"
            case .timedOut:        return "Timed out"
            }
        case .protocolError:        return "Protocol error"
        case .requiredFieldMissing: return "Protocol error"
        case .ukey2:                return "Handshake failed"
        case .inputOutput:          return "Connection lost"
        }
    }
    return error.localizedDescription
}
