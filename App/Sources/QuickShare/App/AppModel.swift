import SwiftUI
import Combine
import AppKit

enum AppMode: String, CaseIterable, Identifiable {
    case send = "Send"
    case receive = "Receive"
    var id: String { rawValue }
    var symbol: String { self == .send ? "arrow.up.circle.fill" : "arrow.down.circle.fill" }
}

/// State of the send flow.
///
/// Quick Share has no "connect, then later choose files" step — the handshake
/// happens when files are offered. The `qr*` states cover reaching a device
/// that isn't in the discovery list: stage files, show a QR, and when a device
/// scans it the transfer starts automatically.
enum ConnectionState: Equatable {
    case idle
    case staging(RemoteDevice)                       // device picked, choosing files
    case connecting(RemoteDevice)                    // offer sent, handshaking
    case awaitingConsent(RemoteDevice, pin: String)  // PIN shown, waiting for remote

    case qrStaging                                   // QR mode, choosing files (no device yet)
    case qrShowing(payload: String)                  // QR displayed, waiting for a scan

    var device: RemoteDevice? {
        switch self {
        case .staging(let d), .connecting(let d), .awaitingConsent(let d, _): return d
        default: return nil
        }
    }
}

/// Single source of truth for the whole app. Views observe this; it consumes
/// engine callbacks and updates published state.
@MainActor
final class AppModel: ObservableObject {

    // Global
    @Published var mode: AppMode = .send
    @Published var deviceName: String = AppModel.defaultDeviceName()

    // Receive side
    @Published var isVisible: Bool = false
    @Published var incomingRequest: IncomingRequest? = nil

    // Send side
    @Published var discoveredDevices: [RemoteDevice] = []
    @Published var connection: ConnectionState = .idle
    @Published var stagedFiles: [FileItem] = []

    // Both
    @Published var transfers: [ActiveTransfer] = []

    /// Device names the user chose to auto-accept from (persisted).
    @Published var trustedDevices: [String] = []
    private let trustKey = "trustedDeviceNames"

    private let service: QuickShareService

    init(service: QuickShareService? = nil) {
        // Defaults to the real engine. Set QS_MOCK=1 for the simulated engine.
        if let service {
            self.service = service
        } else if ProcessInfo.processInfo.environment["QS_MOCK"] != nil {
            self.service = MockQuickShareService()
        } else {
            self.service = NearbyQuickShareService()
        }
        self.trustedDevices = UserDefaults.standard.stringArray(forKey: trustKey) ?? []
        self.service.delegate = self
    }

    /// Menu-bar glyph reflecting the current state.
    var menuBarSymbol: String {
        if incomingRequest != nil { return "arrow.down.circle.fill" }
        if transfers.contains(where: { $0.phase == .transferring }) { return "arrow.up.arrow.down.circle.fill" }
        return isVisible ? "arrow.2.circlepath.circle.fill" : "arrow.2.circlepath"
    }

    // MARK: Trusted devices

    func isTrusted(_ name: String) -> Bool { trustedDevices.contains(name) }

    func trust(_ name: String) {
        guard !isTrusted(name) else { return }
        trustedDevices.append(name)
        persistTrust()
    }

    func untrust(_ name: String) {
        trustedDevices.removeAll { $0 == name }
        persistTrust()
    }

    private func persistTrust() {
        UserDefaults.standard.set(trustedDevices, forKey: trustKey)
    }

    // MARK: Intents — Receive

    func toggleVisibility() {
        isVisible ? service.stopAdvertising() : service.startAdvertising(deviceName: deviceName)
    }

    func respondToIncoming(accept: Bool, trustDevice: Bool = false) {
        guard let req = incomingRequest else { return }
        if accept {
            if trustDevice { trust(req.device.name) }
            acceptIncoming(req)
        } else {
            service.respondToIncoming(id: req.id, accept: false)
        }
        incomingRequest = nil
    }

    /// Accept a request and create its transfer row (shared by manual and
    /// trusted-device auto-accept).
    private func acceptIncoming(_ req: IncomingRequest) {
        service.respondToIncoming(id: req.id, accept: true)
        transfers.insert(
            ActiveTransfer(id: req.id, direction: .incoming, deviceName: req.device.name,
                           title: req.summary, totalBytes: req.totalBytes, phase: .transferring,
                           files: req.fileNames.map { TransferFile(name: $0) }),
            at: 0)
    }

    // MARK: Intents — Send

    func startDiscovery() {
        discoveredDevices = []
        service.startDiscovery()
    }

    func stopDiscovery() { service.stopDiscovery() }

    /// Pick a listed device to send to. Opens the file staging UI.
    func selectDevice(_ device: RemoteDevice) {
        connection = .staging(device)
    }

    func cancelSend() {
        if let device = connection.device {
            service.cancelTransfer(id: device.id)
        }
        if case .qrShowing = connection { service.cancelQRCode() }
        if case .qrStaging = connection { service.cancelQRCode() }
        connection = .idle
        stagedFiles = []
    }

    func stage(urls: [URL]) {
        let items = urls.compactMap { url -> FileItem? in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            return FileItem(url: url, sizeBytes: size)
        }
        for item in items where !stagedFiles.contains(where: { $0.url == item.url }) {
            stagedFiles.append(item)
        }
    }

    func removeStaged(_ item: FileItem) {
        stagedFiles.removeAll { $0.id == item.id }
    }

    /// Begin the handshake + file offer to a listed device.
    func sendStagedFiles() {
        guard case .staging(let device) = connection, !stagedFiles.isEmpty else { return }
        connection = .connecting(device)
        service.sendFiles(stagedFiles, to: device)
    }

    // MARK: Intents — QR send

    /// Enter QR mode from the discovery list (device not shown → offer a QR).
    func startQRSend() {
        connection = .qrStaging
    }

    /// Show the QR once files are staged; a scan then triggers the transfer.
    func showQRCode() {
        guard case .qrStaging = connection, !stagedFiles.isEmpty,
              let payload = service.prepareQRCode() else { return }
        connection = .qrShowing(payload: payload)
    }

    // MARK: Intents — Both

    func cancel(_ transfer: ActiveTransfer) {
        service.cancelTransfer(id: transfer.id)
    }

    func clearFinishedTransfers() {
        transfers.removeAll { $0.phase.isTerminal }
    }

    // MARK: Helpers

    private static func defaultDeviceName() -> String {
        Host.current().localizedName ?? "Mac"
    }
}

// MARK: - Engine callbacks

extension AppModel: QuickShareServiceDelegate {

    func serviceDidUpdateVisibility(isVisible: Bool) {
        self.isVisible = isVisible
    }

    func serviceDidReceiveIncomingRequest(_ request: IncomingRequest) {
        if isTrusted(request.device.name) {
            acceptIncoming(request)   // remembered device → accept automatically
        } else {
            incomingRequest = request
            NSApp.activate(ignoringOtherApps: true)   // surface the prompt
        }
    }

    func serviceDidDiscover(_ device: RemoteDevice) {
        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            discoveredDevices.append(device)
        }
    }

    func serviceDidLose(deviceID: String) {
        discoveredDevices.removeAll { $0.id == deviceID }
    }

    func serviceDidMatchQRDevice(_ device: RemoteDevice) {
        // A device scanned our QR. If we're waiting with files staged, send them.
        guard case .qrShowing = connection, !stagedFiles.isEmpty else { return }
        connection = .connecting(device)
        service.sendFiles(stagedFiles, to: device)
    }

    func serviceDidEstablishConnection(with device: RemoteDevice, pin: String) {
        connection = .awaitingConsent(device, pin: pin)
    }

    func serviceDidFailConnection(with device: RemoteDevice, error: String) {
        if connection.device?.id == device.id { connection = .idle }
    }

    func serviceDidAcceptTransfer(id: String) {
        if let i = transfers.firstIndex(where: { $0.id == id && !$0.phase.isTerminal }) {
            transfers[i].phase = .transferring
        } else {
            let device = connection.device
            let title = stagedFiles.count == 1 ? stagedFiles.first?.name ?? "1 file"
                                               : "\(stagedFiles.count) files"
            let total = stagedFiles.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let files = stagedFiles.map { TransferFile(name: $0.name, url: $0.url) }
            transfers.removeAll { $0.id == id && $0.phase.isTerminal }
            transfers.insert(
                ActiveTransfer(id: id, direction: .outgoing, deviceName: device?.name ?? "Device",
                               title: title, totalBytes: total, phase: .transferring, files: files),
                at: 0)
            stagedFiles = []
            connection = .idle
        }
    }

    func serviceDidUpdateProgress(id: String, fraction: Double) {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[i].fraction = fraction
        if transfers[i].phase != .transferring { transfers[i].phase = .transferring }
    }

    func serviceDidFinishTransfer(id: String, error: String?) {
        if let i = transfers.firstIndex(where: { $0.id == id && !$0.phase.isTerminal }) {
            transfers[i].phase = error == nil ? .completed : .failed(error!)
            if error == nil { transfers[i].fraction = 1.0 }
        }
        if connection.device?.id == id { connection = .idle; stagedFiles = [] }
    }

    func serviceDidResolveFiles(id: String, files: [TransferFile]) {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[i].files = files
    }
}
