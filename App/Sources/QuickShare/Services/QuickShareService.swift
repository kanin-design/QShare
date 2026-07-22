import Foundation

/// Abstraction over the Quick Share protocol engine.
///
/// The dummy build ships `MockQuickShareService`; the real build ships
/// `NearbyQuickShareService`, which wraps NearbyShareKit's
/// `NearbyConnectionManager`. Same interface, so no UI code changes.
///
/// Method groupings follow NearDrop's split:
///   - receive side  ≈ MainAppDelegate (become visible, consent to incoming)
///   - send side     ≈ ShareExtensionDelegate (discover, connect, push files, QR)
@MainActor
protocol QuickShareService: AnyObject {
    var delegate: QuickShareServiceDelegate? { get set }

    // MARK: Receive side (this Mac is the receiver/server)

    /// Advertise this Mac over mDNS and start the TCP listener.
    func startAdvertising(deviceName: String)
    func stopAdvertising()

    /// Answer an `incomingTransferRequest` after the user chose.
    func respondToIncoming(id: String, accept: Bool)

    /// Where received files should be saved.
    func setReceiveDirectory(_ url: URL)

    // MARK: Send side (this Mac is the sender/client)

    /// Browse for nearby receivers.
    func startDiscovery()
    func stopDiscovery()

    /// Connect to `device` and push `files`. Handshake + PIN happen during this
    /// call (PIN via `serviceDidEstablishConnection`), then
    /// `serviceDidAcceptTransfer` once the remote user accepts.
    func sendFiles(_ files: [FileItem], to device: RemoteDevice)

    /// Cancel an in-flight incoming or outgoing transfer.
    func cancelTransfer(id: String)

    // MARK: QR send (reach a device that isn't in the discovery list)

    /// Generate a Quick Share QR payload (a `quickshare.google` App Link URL).
    /// When an Android device scans it, it becomes discoverable and the engine
    /// reports it via `serviceDidMatchQRDevice` — at which point the caller
    /// pushes the staged files to it. Returns nil if QR isn't available.
    func prepareQRCode() -> String?

    /// Tear down a pending QR offer.
    func cancelQRCode()
}

/// Callbacks from the engine, delivered on the main actor.
@MainActor
protocol QuickShareServiceDelegate: AnyObject {
    // Receive side
    func serviceDidUpdateVisibility(isVisible: Bool)
    func serviceDidReceiveIncomingRequest(_ request: IncomingRequest)

    // Send side
    func serviceDidDiscover(_ device: RemoteDevice)
    func serviceDidLose(deviceID: String)
    func serviceDidEstablishConnection(with device: RemoteDevice, pin: String)
    func serviceDidFailConnection(with device: RemoteDevice, error: String)

    /// A device scanned our QR and is now reachable — send it the staged files.
    func serviceDidMatchQRDevice(_ device: RemoteDevice)

    // Both directions
    func serviceDidAcceptTransfer(id: String)
    func serviceDidUpdateProgress(id: String, fraction: Double)
    func serviceDidFinishTransfer(id: String, error: String?)

    /// Resolved on-disk locations for a transfer's files (incoming: where they
    /// were saved). Lets the UI open/reveal them.
    func serviceDidResolveFiles(id: String, files: [TransferFile])
}
