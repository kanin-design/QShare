import SwiftUI
import Combine
import AppKit

enum AppMode: String, CaseIterable, Identifiable {
    case send = "Send"
    case receive = "Receive"
    var id: String { rawValue }
    var symbol: String { self == .send ? "arrow.up.circle.fill" : "arrow.down.circle.fill" }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
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

    /// Names of devices we've accepted from before (persisted).
    ///
    /// This is a *convenience hint only* — it surfaces "you've accepted from this
    /// name before" on the incoming prompt. It deliberately does not auto-accept.
    ///
    /// Quick Share gives us no stable device identity to key trust on: the UKEY2
    /// keys are freshly generated per handshake, and the paired-key/certificate
    /// frames that would carry a persistent identity are stubbed out in the
    /// vendored engine (it answers `pairedKeyResult = .unable`). The device name
    /// is remote-supplied and unauthenticated, so auto-accepting on it would let
    /// anything on the LAN write to the receive folder just by claiming the name.
    @Published var knownDevices: [String] = []
    private let knownKey = "knownDeviceNames"
    /// Superseded by `knownKey`; cleared on launch so no one keeps an
    /// auto-accept list that used to bypass the prompt.
    private let legacyTrustKey = "trustedDeviceNames"

    // Settings (persisted)
    @Published var downloadDirectory: URL = AppModel.defaultDownloadDirectory()
    @Published var startVisible: Bool = false
    @Published var appearance: AppAppearance = .system
    /// Localhost control API for the `qshare` CLI. Off by default: it can read
    /// any path the user can and push it to a nearby device, so it's opt-in.
    @Published var controlAPIEnabled: Bool = false
    private let downloadDirKey = "downloadDirectoryPath"
    private let startVisibleKey = "startVisible"
    private let appearanceKey = "appearance"
    private let controlAPIKey = "controlAPIEnabled"

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
        // Migrate off the old name-keyed auto-accept list. Those entries used to
        // bypass the prompt entirely, so they are carried over as display-only
        // "known" names and the old key is removed.
        let defaults = UserDefaults.standard
        if let legacy = defaults.stringArray(forKey: legacyTrustKey) {
            let merged = (defaults.stringArray(forKey: knownKey) ?? []) + legacy
            defaults.set(Array(Set(merged)).sorted(), forKey: knownKey)
            defaults.removeObject(forKey: legacyTrustKey)
        }
        self.knownDevices = defaults.stringArray(forKey: knownKey) ?? []
        if let path = defaults.string(forKey: downloadDirKey) {
            self.downloadDirectory = URL(fileURLWithPath: path)
        }
        self.startVisible = defaults.bool(forKey: startVisibleKey)
        self.controlAPIEnabled = defaults.bool(forKey: controlAPIKey)
        if let a = defaults.string(forKey: appearanceKey),
           let parsed = AppAppearance(rawValue: a) { self.appearance = parsed }
        self.service.delegate = self
        self.service.setReceiveDirectory(downloadDirectory)
        if startVisible { self.service.startAdvertising(deviceName: deviceName) }
        // Discover continuously so the menu-bar list is always current.
        self.service.startDiscovery()
        if controlAPIEnabled { startControlServer() }

        if ProcessInfo.processInfo.environment["QS_MOCK"] != nil {
            deviceName = "MacBook Pro"   // neutral name for demo screenshots
            seedDemoTransfers()
        }
    }

    /// Neutral, demo-safe sample transfers (no real filenames, people, or devices)
    /// so QS_MOCK=1 is presentable for screenshots.
    private func seedDemoTransfers() {
        let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        func file(_ n: String) -> TransferFile { TransferFile(name: n, url: dl.appendingPathComponent(n)) }

        let devices = ["Pixel 8 Pro", "Galaxy S24", "Galaxy Tab S9"]
        // (filename, direction, bytes) — newest first
        let items: [(String, TransferDirection, Int64)] = [
            ("Mountain-sunset.jpg", .outgoing,  1_800_000),
            ("Release-notes.pdf",   .incoming,    320_000),
            ("IMG_2481.heic",       .outgoing,  4_500_000),
            ("Product-demo.mp4",    .incoming, 58_000_000),
            ("Ambient-loop.mp3",    .outgoing,  6_200_000),
            ("Screenshot.png",      .incoming,    980_000),
            ("Design-assets.zip",   .outgoing, 24_000_000),
            ("Slides.key",          .incoming, 12_400_000),
        ]
        var demo: [ActiveTransfer] = items.enumerated().map { i, it in
            ActiveTransfer(id: "demo-\(i)", direction: it.1, deviceName: devices[i % devices.count],
                           title: it.0, totalBytes: it.2, fraction: 1, phase: .completed, files: [file(it.0)])
        }

        // One in-progress transfer at the top for a richer screenshot.
        demo.insert(ActiveTransfer(id: "demo-live", direction: .outgoing, deviceName: "Pixel 8 Pro",
                                   title: "Travel-video.mov", totalBytes: 84_000_000, fraction: 0.62,
                                   phase: .transferring, files: [file("Travel-video.mov")]), at: 0)

        // Two multi-file groups (one sent, one received).
        let g1 = ["Beach-01.jpg", "Beach-02.jpg", "Beach-03.jpg"]
        demo.append(ActiveTransfer(id: "demo-g1", direction: .outgoing, deviceName: "Galaxy Tab S9",
                                   title: "3 files", totalBytes: 8_400_000, fraction: 1,
                                   phase: .completed, files: g1.map(file)))
        let g2 = ["Clip-01.mp4", "Clip-02.mp4", "Voice-note.m4a", "Cover.png", "Readme.txt"]
        demo.append(ActiveTransfer(id: "demo-g2", direction: .incoming, deviceName: "Galaxy S24",
                                   title: "5 files", totalBytes: 210_000_000, fraction: 1,
                                   phase: .completed, files: g2.map(file)))
        transfers = demo
    }

    // MARK: CLI / control API

    private var controlServer: ControlServer?
    struct CliSendResult { let ok: Bool; let pin: String?; let error: String? }
    private var cliPending: [String: (CliSendResult) -> Void] = [:]
    private var cliPins: [String: String] = [:]

    func devicesForCLI() -> [[String: Any]] {
        availableDevices.map { ["name": $0.name, "id": $0.id, "type": $0.type.rawValue, "known": isKnown($0.name)] }
    }

    func transfersForCLI() -> [[String: Any]] {
        transfers.map {
            ["title": $0.title, "device": $0.deviceName, "percent": Int($0.fraction * 100),
             "phase": "\($0.phase)"]
        }
    }

    /// Send files to a device by name (or id), invoking `completion` when the
    /// transfer finishes. Reuses the normal send flow so the GUI reflects it.
    func cliSend(paths: [String], to name: String, completion: @escaping (CliSendResult) -> Void) {
        // The send flow is single-slot and shares its state with the window, so a
        // CLI send while the user is mid-flow would silently discard their staged
        // files. Refuse instead of clobbering.
        guard case .idle = connection, cliPending.isEmpty else {
            completion(CliSendResult(ok: false, pin: nil, error: "busy")); return
        }
        guard let device = discoveredDevices.first(where: { $0.name == name || $0.id == name }) else {
            completion(CliSendResult(ok: false, pin: nil, error: "device_not_found")); return
        }
        let files = paths.compactMap { p -> FileItem? in
            let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            return FileItem(url: url, sizeBytes: size)
        }
        guard !files.isEmpty else { completion(CliSendResult(ok: false, pin: nil, error: "no_readable_files")); return }
        cliPending[device.id] = completion
        stagedFiles = files
        connection = .connecting(device)
        service.sendFiles(files, to: device)
        scheduleConnectTimeout(for: device)
    }

    private func finishCli(_ deviceID: String, ok: Bool, error: String?) {
        guard let completion = cliPending.removeValue(forKey: deviceID) else { return }
        completion(CliSendResult(ok: ok, pin: cliPins.removeValue(forKey: deviceID), error: error))
    }

    /// Release every parked CLI request (used when the control API is switched
    /// off mid-flight, so no HTTP client is left hanging).
    private func failAllPendingCli(error: String) {
        let pending = cliPending
        cliPending.removeAll()
        cliPins.removeAll()
        for (_, completion) in pending {
            completion(CliSendResult(ok: false, pin: nil, error: error))
        }
    }

    /// Devices currently reachable, previously-seen ones first. Sorted by name
    /// within each group so the list has a stable order (`sorted` is not stable,
    /// so ranking alone let equal-rank rows shuffle between renders).
    var availableDevices: [RemoteDevice] {
        discoveredDevices.sorted {
            isKnown($0.name) == isKnown($1.name) ? $0.name < $1.name : isKnown($0.name)
        }
    }

    /// Jump into the send flow targeting a specific device (from the menu).
    func prepareSend(to device: RemoteDevice) {
        mode = .send
        connection = .staging(device)
    }

    // MARK: Settings

    func setDownloadDirectory(_ url: URL) {
        downloadDirectory = url
        UserDefaults.standard.set(url.path, forKey: downloadDirKey)
        service.setReceiveDirectory(url)
    }

    func setStartVisible(_ on: Bool) {
        startVisible = on
        UserDefaults.standard.set(on, forKey: startVisibleKey)
    }

    func setControlAPIEnabled(_ on: Bool) {
        controlAPIEnabled = on
        UserDefaults.standard.set(on, forKey: controlAPIKey)
        if on {
            startControlServer()
        } else {
            controlServer?.stop()
            controlServer = nil
            // Any CLI request still parked on a completion would otherwise hang.
            failAllPendingCli(error: "control_api_disabled")
        }
    }

    private func startControlServer() {
        guard controlServer == nil else { return }
        let server = ControlServer(model: self)
        controlServer = server
        server.start()
    }

    func setAppearance(_ a: AppAppearance) {
        appearance = a
        UserDefaults.standard.set(a.rawValue, forKey: appearanceKey)
    }

    private static func defaultDownloadDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    /// Menu-bar glyph reflecting the current state.
    var menuBarSymbol: String {
        if incomingRequest != nil { return "arrow.down.circle.fill" }
        if transfers.contains(where: { $0.phase == .transferring }) { return "arrow.up.arrow.down.circle.fill" }
        return isVisible ? "arrow.2.circlepath.circle.fill" : "arrow.2.circlepath"
    }

    // MARK: Known devices (display hint only — never an accept decision)

    func isKnown(_ name: String) -> Bool { knownDevices.contains(name) }

    func remember(_ name: String) {
        guard !isKnown(name) else { return }
        knownDevices.append(name)
        persistKnown()
    }

    func forget(_ name: String) {
        knownDevices.removeAll { $0 == name }
        persistKnown()
    }

    private func persistKnown() {
        UserDefaults.standard.set(knownDevices, forKey: knownKey)
    }

    // MARK: Intents — Receive

    func toggleVisibility() {
        isVisible ? service.stopAdvertising() : service.startAdvertising(deviceName: deviceName)
    }

    func respondToIncoming(accept: Bool) {
        guard let req = incomingRequest else { return }
        if accept {
            remember(req.device.name)
            acceptIncoming(req)
        } else {
            service.respondToIncoming(id: req.id, accept: false)
        }
        incomingRequest = nil
    }

    /// Accept a request and create its transfer row.
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
        scheduleConnectTimeout(for: device)
    }

    /// One token per device — a shared counter meant a second send silently
    /// invalidated the first one's timeout, leaving it to hang forever.
    private var connectTokens: [String: Int] = [:]

    /// If the handshake doesn't produce a PIN within a few seconds, the connect
    /// failed (device moved on / unreachable). Don't hang — fail cleanly.
    private func scheduleConnectTimeout(for device: RemoteDevice) {
        let token = (connectTokens[device.id] ?? 0) + 1
        connectTokens[device.id] = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, token == self.connectTokens[device.id],
                  case .connecting(let d) = self.connection, d.id == device.id else { return }
            self.connectTokens[device.id] = nil
            self.service.cancelTransfer(id: device.id)
            self.connection = .idle
            self.stagedFiles = []
            self.transfers.insert(
                ActiveTransfer(id: "fail-\(UUID().uuidString.prefix(6))", direction: .outgoing,
                               deviceName: device.name, title: "Couldn’t connect",
                               totalBytes: 0, phase: .failed("No response — try again")),
                at: 0)
            self.finishCli(device.id, ok: false, error: "timeout")
        }
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
        // Always ask. The sender's name is unauthenticated, so there is nothing
        // here we could safely auto-accept on — see `knownDevices`.
        incomingRequest = request
        // `NSApp` is an implicitly-unwrapped global that is nil outside a running
        // GUI app. This path is driven by network input, so don't force it.
        if let app = NSApp { app.activate(ignoringOtherApps: true) }   // surface the prompt
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
        scheduleConnectTimeout(for: device)
    }

    func serviceDidEstablishConnection(with device: RemoteDevice, pin: String) {
        connection = .awaitingConsent(device, pin: pin)
        if cliPending[device.id] != nil { cliPins[device.id] = pin }
    }

    func serviceDidFailConnection(with device: RemoteDevice, error: String) {
        if connection.device?.id == device.id { connection = .idle }
        finishCli(device.id, ok: false, error: error)
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
        finishCli(id, ok: error == nil, error: error)
    }

    func serviceDidResolveFiles(id: String, files: [TransferFile]) {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[i].files = files
    }
}
