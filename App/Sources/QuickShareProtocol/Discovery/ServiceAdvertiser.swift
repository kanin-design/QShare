import Foundation
import Network

/// Advertises this Mac over mDNS and accepts incoming connections.
///
/// Visibility is reported from what actually happened — the listener becoming
/// ready and Bonjour confirming the publish — never from the fact that we asked.
/// A UI that says "visible" while nothing is listening is worse than one that
/// says nothing.
@MainActor
public final class ServiceAdvertiser {

    public static let serviceType = "_FC9F5ED42C8A._tcp."

    /// Called when advertising actually starts or stops.
    public var onVisibilityChange: (@MainActor (Bool) -> Void)?
    /// Called with each accepted connection.
    public var onConnection: (@MainActor (NWConnection, String) -> Void)?

    private var listener: NWListener?
    private var netService: NetService?
    private var serviceDelegate: PublishObserver?
    private let endpointID: [UInt8]
    private var deviceName: String
    private var isRequested = false
    private var reportedVisible = false

    public init(deviceName: String, endpointID: [UInt8]) {
        self.deviceName = deviceName
        self.endpointID = endpointID
    }

    public func updateDeviceName(_ name: String) {
        guard name != deviceName else { return }
        deviceName = name
        // Republish so peers see the new name.
        if isRequested {
            stop()
            start()
        }
    }

    public func start() {
        // Starting an already-started listener is invalid, and visibility is
        // reported asynchronously, so the caller can legitimately ask twice
        // before the first attempt resolves.
        guard !isRequested else { return }
        isRequested = true

        // A cancelled NWListener can never be restarted, so always build a fresh
        // one. Deciding this from an explicit flag rather than by polling
        // `listener.state` avoids racing cancel(), which is asynchronous.
        guard let listener = try? NWListener(using: makeParameters()) else {
            isRequested = false
            report(false)
            return
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.publishBonjour()
                case .failed, .cancelled:
                    self.report(false)
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.onConnection?(connection, UUID().uuidString)
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    public func stop() {
        isRequested = false
        netService?.stop()
        netService = nil
        serviceDelegate = nil
        listener?.cancel()
        listener = nil
        report(false)
    }

    private func makeParameters() -> NWParameters {
        let params = NWParameters(tls: nil, tcp: .init())
        params.includePeerToPeer = false
        return params
    }

    private func publishBonjour() {
        guard isRequested, let port = listener?.port else {
            report(false)
            return
        }

        // The service name encodes a fixed prefix plus our endpoint id.
        let nameBytes: [UInt8] = [
            0x23,                                                    // PCP
            endpointID[0], endpointID[1], endpointID[2], endpointID[3],
            0xFC, 0x9F, 0x5E,                                        // service id hash
            0, 0,
        ]
        let serviceName = Data(nameBytes).urlSafeBase64EncodedString()
        let info = EndpointInfo(name: deviceName, deviceType: .computer)
        guard let txtValue = info.serialized().urlSafeBase64EncodedString().data(using: .utf8) else {
            report(false)
            return
        }

        let service = NetService(domain: "", type: Self.serviceType,
                                 name: serviceName, port: Int32(port.rawValue))
        // NetService delivers its delegate callbacks on the run loop it was
        // scheduled on. This runs on the main actor, whose run loop is live, so
        // didPublish/didNotPublish actually arrive — publishing from a bare
        // dispatch queue leaves them silently unfired.
        let observer = PublishObserver { [weak self] visible in
            Task { @MainActor in self?.report(visible) }
        }
        service.delegate = observer
        service.setTXTRecord(NetService.data(fromTXTRecord: ["n": txtValue]))
        serviceDelegate = observer
        netService = service
        service.publish()
    }

    private func report(_ visible: Bool) {
        guard reportedVisible != visible else { return }
        reportedVisible = visible
        onVisibilityChange?(visible)
    }
}

/// Bridges NetService's delegate callbacks back to the advertiser.
///
/// `NetServiceDelegate` is not actor-isolated, so the callback is handed a
/// `@Sendable` reporter that hops to the main actor itself rather than assuming
/// it is already there. Holding only that immutable closure is what makes the
/// unchecked conformance honest.
private final class PublishObserver: NSObject, NetServiceDelegate, @unchecked Sendable {
    private let report: @Sendable (Bool) -> Void

    init(report: @escaping @Sendable (Bool) -> Void) {
        self.report = report
    }

    func netServiceDidPublish(_ sender: NetService) {
        report(true)
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        NSLog("QShare: mDNS publish failed: \(errorDict)")
        report(false)
    }

    func netServiceDidStop(_ sender: NetService) {
        report(false)
    }
}

// MARK: - URL-safe base64

extension Data {
    /// Base64 with the URL-safe alphabet and no padding, as the protocol uses.
    func urlSafeBase64EncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    static func fromUrlSafeBase64(_ string: String) -> Data? {
        var normalized = string
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
        while normalized.count % 4 != 0 { normalized += "=" }
        return Data(base64Encoded: normalized, options: .ignoreUnknownCharacters)
    }
}
