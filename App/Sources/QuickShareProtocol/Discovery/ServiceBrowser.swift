import Foundation
import Network

/// Browses for nearby Quick Share receivers over mDNS.
@MainActor
public final class ServiceBrowser {

    public var onFound: (@MainActor (QuickShareDevice, NWEndpoint) -> Void)?
    public var onLost: (@MainActor (String) -> Void)?
    /// A device that scanned our QR code has appeared.
    public var onQRMatch: (@MainActor (QuickShareDevice) -> Void)?

    /// Set while a QR code is on screen, so we can spot the scanner.
    public var qrSession: QRCodeSession?

    private var browser: NWBrowser?
    private var found: [String: NWEndpoint] = [:]

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: ServiceAdvertiser.serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] _, changes in
            Task { @MainActor in
                guard let self else { return }
                for change in changes {
                    switch change {
                    case .added(let result):   self.handleFound(result)
                    case .removed(let result): self.handleLost(result)
                    default: break
                    }
                }
            }
        }
        // Release the reference only once the browse has actually reached
        // `.cancelled` — see `stop()`.
        browser.stateUpdateHandler = { [weak self] state in
            guard case .cancelled = state else { return }
            Task { @MainActor in
                guard let self, self.browser === browser else { return }
                browser.browseResultsChangedHandler = nil
                browser.stateUpdateHandler = nil
                self.browser = nil
            }
        }
        browser.start(queue: .global(qos: .userInitiated))
    }

    public func stop() {
        guard let browser else { return }
        // `cancel()` is asynchronous. Dropping the last strong reference here —
        // which is what `browser = nil` straight after `cancel()` used to do —
        // leaves the underlying nw_browser mid-teardown with its handlers still
        // registered, and it never finishes: the process kept taking mDNS
        // multicast wakeups (~7% of a core, sustained) long after discovery was
        // supposedly stopped. Hold the reference and let `stateUpdateHandler`
        // clear it when cancellation completes.
        browser.cancel()
        found.removeAll()
    }

    /// The endpoint to dial for a device we've seen.
    public func endpoint(for deviceID: String) -> NWEndpoint? { found[deviceID] }

    private func handleFound(_ result: NWBrowser.Result) {
        // Ignore our own advertisement.
        for interface in result.interfaces where interface.type == .loopback { return }

        guard let endpointID = Self.endpointID(for: result),
              case let .bonjour(txtRecord) = result.metadata,
              let encoded = txtRecord.dictionary["n"],
              let raw = Data.fromUrlSafeBase64(encoded),
              let info = try? EndpointInfo(serialized: raw) else { return }

        // A device that scanned our code advertises a token derived from it, and
        // may be otherwise invisible — its name arrives encrypted instead.
        if let qrSession, let qrData = info.qrCodeData {
            if qrSession.matches(advertisedQRData: qrData) {
                found[endpointID] = result.endpoint
                let name = info.name ?? "Scanned device"
                onQRMatch?(QuickShareDevice(id: endpointID, name: name, type: info.deviceType))
                return
            }
            if let decrypted = qrSession.decryptDeviceName(from: qrData) {
                found[endpointID] = result.endpoint
                onQRMatch?(QuickShareDevice(id: endpointID, name: decrypted, type: info.deviceType))
                return
            }
        }

        // A nameless advertisement can't be shown to the user, so skip it rather
        // than inventing a placeholder.
        guard let name = info.name else { return }

        found[endpointID] = result.endpoint
        onFound?(QuickShareDevice(id: endpointID, name: name, type: info.deviceType),
                 result.endpoint)
    }

    private func handleLost(_ result: NWBrowser.Result) {
        guard let endpointID = Self.endpointID(for: result) else { return }
        found.removeValue(forKey: endpointID)
        onLost?(endpointID)
    }

    private static func endpointID(for result: NWBrowser.Result) -> String? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        return name
    }
}
