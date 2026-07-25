import Foundation
import QuickShareProtocol

/// Adapts `QuickShareEngine` to the app's `QuickShareService` interface.
///
/// The engine is already `@MainActor` and callback-based, so this is a thin
/// translation between its vocabulary (offers, sessions) and the app's
/// (requests, transfers) — no threading work, no state of its own beyond the
/// id bookkeeping the UI needs.
@MainActor
final class NearbyQuickShareService: QuickShareService {

    weak var delegate: QuickShareServiceDelegate?

    private let engine: QuickShareEngine
    /// Maps an engine transfer id to the device it belongs to, so outbound
    /// events can be reported with full context.
    private var outboundDevices: [String: RemoteDevice] = [:]
    /// Incoming offers awaiting the user's answer.
    private var pendingOffers: [String: IncomingOffer] = [:]

    init() {
        engine = QuickShareEngine(
            deviceName: Host.current().localizedName ?? "Mac",
            receiveDirectory: FileManager.default
                .urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads"))
        wireUp()
    }

    private func wireUp() {
        engine.onVisibilityChange = { [weak self] visible in
            self?.delegate?.serviceDidUpdateVisibility(isVisible: visible)
        }

        engine.onDeviceFound = { [weak self] device in
            self?.delegate?.serviceDidDiscover(Self.map(device))
        }

        engine.onDeviceLost = { [weak self] id in
            self?.delegate?.serviceDidLose(deviceID: id)
        }

        engine.onQRDeviceMatched = { [weak self] device in
            self?.delegate?.serviceDidMatchQRDevice(Self.map(device))
        }

        engine.onOfferReceived = { [weak self] offer in
            guard let self else { return }
            self.pendingOffers[offer.id] = offer
            let names = offer.files.isEmpty
                ? [offer.textTitle ?? "Link"]
                : offer.files.map(\.name)
            self.delegate?.serviceDidReceiveIncomingRequest(
                IncomingRequest(id: offer.id,
                                device: Self.map(offer.device),
                                fileNames: names,
                                totalBytes: offer.totalBytes,
                                pin: offer.pinCode))
        }

        engine.onIncomingProgress = { [weak self] id, fraction in
            self?.delegate?.serviceDidUpdateProgress(id: id, fraction: fraction)
        }

        engine.onIncomingFinished = { [weak self] id, urls, error in
            guard let self else { return }
            self.pendingOffers.removeValue(forKey: id)
            if !urls.isEmpty {
                self.delegate?.serviceDidResolveFiles(
                    id: id, files: urls.map { TransferFile(name: $0.lastPathComponent, url: $0) })
            }
            self.delegate?.serviceDidFinishTransfer(id: id, error: error?.userMessage)
        }

        engine.onOutgoingEvent = { [weak self] id, event in
            guard let self else { return }
            let device = self.outboundDevices[id]
            switch event {
            case .connected(let pin):
                if let device {
                    self.delegate?.serviceDidEstablishConnection(with: device, pin: pin)
                }
            case .accepted:
                self.delegate?.serviceDidAcceptTransfer(id: id)
            case .progress(let fraction):
                self.delegate?.serviceDidUpdateProgress(id: id, fraction: fraction)
            case .finished:
                self.outboundDevices.removeValue(forKey: id)
                self.delegate?.serviceDidFinishTransfer(id: id, error: nil)
            case .failed(let error):
                self.outboundDevices.removeValue(forKey: id)
                if let device {
                    self.delegate?.serviceDidFailConnection(with: device, error: error.userMessage)
                }
                self.delegate?.serviceDidFinishTransfer(id: id, error: error.userMessage)
            }
        }
    }

    // MARK: Receive side

    func startAdvertising(deviceName: String) {
        engine.setDeviceName(deviceName)
        engine.startAdvertising()
    }

    func stopAdvertising() {
        engine.stopAdvertising()
    }

    func respondToIncoming(id: String, accept: Bool) {
        engine.respondToOffer(id: id, accept: accept)
    }

    func setReceiveDirectory(_ url: URL) {
        engine.receiveDirectory = url
    }

    // MARK: Send side

    func startDiscovery() { engine.startDiscovery() }
    func stopDiscovery() { engine.stopDiscovery() }

    func sendFiles(_ files: [FileItem], to device: RemoteDevice) {
        let outgoing = files.compactMap { try? OutgoingFile.from(url: $0.url) }
        guard !outgoing.isEmpty else {
            delegate?.serviceDidFailConnection(with: device, error: "Couldn't read those files")
            return
        }
        outboundDevices[device.id] = device
        engine.send(files: outgoing, to: Self.unmap(device))
    }

    func cancelTransfer(id: String) {
        engine.cancelTransfer(id: id)
    }

    // MARK: QR send

    func prepareQRCode() -> String? { engine.beginQRSession() }
    func cancelQRCode() { engine.endQRSession() }

    // MARK: Mapping

    private static func map(_ device: QuickShareDevice) -> RemoteDevice {
        RemoteDevice(id: device.id, name: device.name, type: map(device.type))
    }

    private static func unmap(_ device: RemoteDevice) -> QuickShareDevice {
        QuickShareDevice(id: device.id, name: device.name, type: unmap(device.type))
    }

    private static func map(_ type: QuickShareDevice.DeviceType) -> DeviceType {
        switch type {
        case .phone:    return .phone
        case .tablet:   return .tablet
        case .computer: return .computer
        case .unknown:  return .unknown
        }
    }

    private static func unmap(_ type: DeviceType) -> QuickShareDevice.DeviceType {
        switch type {
        case .phone:    return .phone
        case .tablet:   return .tablet
        case .computer: return .computer
        case .unknown:  return .unknown
        }
    }
}
