import SwiftUI
import Combine
import AppKit
import UserNotifications

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
    /// Drives the ⌘⌥I build-info sheet; set from the menu command.
    @Published var showingBuildInfo = false
    @Published var deviceName: String = AppModel.defaultDeviceName()

    // Receive side
    //
    // Two separate facts, because conflating them makes the UI either lie or
    // lag. `wantsVisible` is what the user asked for and flips instantly, so the
    // switch feels responsive. `isVisible` is what the engine actually achieved
    // — mDNS published — and drives the status text and indicator.
    @Published private(set) var wantsVisible: Bool = false
    @Published private(set) var isVisible: Bool = false
    /// Set when advertising was requested but never came up.
    @Published private(set) var visibilityFailed: Bool = false

    /// Notification permission is asked for at most once per launch — see
    /// `notifyAutoAccepted`.
    enum NotificationAuthorization {
        case unknown, pending, granted, denied
    }
    private var notificationAuthorization: NotificationAuthorization = .unknown

    /// What to show the user about advertising.
    enum VisibilityStatus: Equatable {
        case off
        case starting
        case on
        case stopping
        case failed
    }

    var visibilityStatus: VisibilityStatus {
        if visibilityFailed { return .failed }
        switch (wantsVisible, isVisible) {
        case (true, true):   return .on
        case (true, false):  return .starting
        case (false, true):  return .stopping
        case (false, false): return .off
        }
    }
    @Published var incomingRequest: IncomingRequest? = nil
    /// Bumped on every incoming request, accepted automatically or not.
    /// `AppModel` can't call `openWindow` itself — that's a View-only
    /// environment action — so this is what a View (`MenuBarView`, always
    /// alive via the menu-bar item) watches to reopen the main window when
    /// it was closed and something just happened that the user should see.
    @Published private(set) var incomingActivityToken = UUID()

    // Send side
    @Published var discoveredDevices: [RemoteDevice] = []
    @Published var connection: ConnectionState = .idle
    @Published var stagedFiles: [FileItem] = []

    // Both
    @Published var transfers: [ActiveTransfer] = []

    /// Recently transferred files, newest first, for the File menu.
    @Published var recentFiles: [RecentFile] = []
    private static let maxRecentFiles = 10

    /// Senders we've accepted from before, and whether to auto-accept from them.
    ///
    /// Auto-accept is per-device and opt-in — never the default for a device just
    /// because you accepted from it once.
    ///
    /// Worth knowing what it can and can't promise: the only thing a sender
    /// proves is the name it chose to advertise. Quick Share exposes no
    /// verifiable device identity here (UKEY2 keys are per-handshake, and the
    /// certificate frames that would carry one are stubbed), so a device on your
    /// network that claims a name you've enabled will be auto-accepted. That's
    /// why auto-accepted transfers still post a notification instead of landing
    /// silently.
    @Published var knownDevices: [KnownDevice] = []

    // Settings (persisted)
    @Published var downloadDirectory: URL = AppModel.defaultDownloadDirectory()
    @Published var startVisible: Bool = false
    @Published var appearance: AppAppearance = .system
    /// Live system dark/light, so "System" can resolve to a concrete
    /// ColorScheme rather than nil — `.preferredColorScheme(nil)` doesn't
    /// reliably reset a window that was previously forced to Light or Dark,
    /// so "System" is expressed as "whichever concrete scheme matches right
    /// now" instead of "no override," and this is what keeps that current.
    @Published private var systemIsDark: Bool = AppModel.currentSystemIsDark()
    private var systemAppearanceObserver: NSObjectProtocol?

    var effectiveColorScheme: ColorScheme {
        switch appearance {
        case .system: return systemIsDark ? .dark : .light
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    private nonisolated static func currentSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
    /// Localhost control API for the `qshare` CLI. Off by default: it can read
    /// any path the user can and push it to a nearby device, so it's opt-in.
    @Published var controlAPIEnabled: Bool = false

    private let service: QuickShareService
    private let prefs = Preferences()

    init(service: QuickShareService? = nil) {
        // Defaults to the real engine. Set QS_MOCK=1 for the simulated engine.
        if let service {
            self.service = service
        } else if ProcessInfo.processInfo.environment["QS_MOCK"] != nil {
            self.service = MockQuickShareService()
        } else {
            self.service = NearbyQuickShareService()
        }
        if let saved = prefs.downloadDirectory { self.downloadDirectory = saved }
        self.startVisible = prefs.startVisible
        self.controlAPIEnabled = prefs.controlAPIEnabled
        self.appearance = prefs.appearance
        self.knownDevices = prefs.loadKnownDevices()
        self.recentFiles = prefs.loadRecentFiles()
        self.service.delegate = self
        self.service.setReceiveDirectory(downloadDirectory)
        if startVisible {
            self.wantsVisible = true
            self.service.startAdvertising(deviceName: deviceName)
        }
        // Discover continuously so the menu-bar list is always current.
        self.service.startDiscovery()
        if controlAPIEnabled { startControlServer() }

        systemAppearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.systemIsDark = AppModel.currentSystemIsDark() }
        }

        if ProcessInfo.processInfo.environment["QS_MOCK"] != nil {
            deviceName = "MacBook Pro"   // neutral name for demo screenshots
            transfers = DemoData.transfers()
        }
    }

    deinit {
        systemAppearanceObserver.map(DistributedNotificationCenter.default().removeObserver)
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

    // MARK: Debug (QS_MOCK only — see ControlServer's /debug/* gating)

    /// Synthesizes an incoming request as if it had just arrived over the
    /// network, exercising the exact same path a real one takes — auto-accept
    /// check, app activation, the window-reopen token — from a single CLI
    /// call instead of a GUI test run.
    func debugFireIncomingRequest(deviceName: String, files: [String], bytes: Int64, pin: String) {
        let request = IncomingRequest(
            id: "debug-\(UUID().uuidString.prefix(6))",
            device: RemoteDevice(id: "debug-\(deviceName)", name: deviceName, type: .phone),
            fileNames: files.isEmpty ? ["debug-file.txt"] : files,
            totalBytes: bytes,
            pin: pin)
        serviceDidReceiveIncomingRequest(request)
    }

    /// What the system has actually recorded as delivered, plus current
    /// permission status — the only reliable way to confirm a notification
    /// really reached the system, rather than screenshotting a banner that's
    /// gone in a few seconds.
    func debugNotificationStatus(completion: @escaping (_ delivered: [[String: Any]], _ authorization: String) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                let delivered: [[String: Any]] = notifications.map {
                    ["id": $0.request.identifier,
                     "title": $0.request.content.title,
                     "body": $0.request.content.body]
                }
                let authorization: String
                switch settings.authorizationStatus {
                case .authorized:    authorization = "authorized"
                case .denied:        authorization = "denied"
                case .notDetermined: authorization = "notDetermined"
                case .provisional:   authorization = "provisional"
                case .ephemeral:     authorization = "ephemeral"
                @unknown default:    authorization = "unknown"
                }
                Task { @MainActor in completion(delivered, authorization) }
            }
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
        prefs.downloadDirectory = url
        service.setReceiveDirectory(url)
    }

    func setStartVisible(_ on: Bool) {
        startVisible = on
        prefs.startVisible = on
    }

    func setControlAPIEnabled(_ on: Bool) {
        controlAPIEnabled = on
        prefs.controlAPIEnabled = on
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
        prefs.appearance = a
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

    // MARK: Recent files

    /// Records the files of a completed transfer, newest first.
    private func recordRecentFiles(from transfer: ActiveTransfer) {
        let incoming = transfer.direction == .incoming
        let entries = transfer.files.compactMap { file -> RecentFile? in
            guard let url = file.url else { return nil }
            return RecentFile(name: file.name, path: url.path,
                              receivedAt: Date(), wasIncoming: incoming)
        }
        guard !entries.isEmpty else { return }

        // Re-transferring a file should move it up, not duplicate it.
        let newPaths = Set(entries.map(\.path))
        recentFiles.removeAll { newPaths.contains($0.path) }
        recentFiles.insert(contentsOf: entries, at: 0)
        if recentFiles.count > Self.maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(Self.maxRecentFiles))
        }
        persistRecentFiles()
    }

    func clearRecentFiles() {
        recentFiles.removeAll()
        persistRecentFiles()
    }

    private func persistRecentFiles() { prefs.save(recentFiles: recentFiles) }

    func openRecentFile(_ file: RecentFile) {
        guard file.stillExists else {
            // Gone from disk — drop it rather than bouncing the Dock icon.
            recentFiles.removeAll { $0.path == file.path }
            persistRecentFiles()
            return
        }
        NSWorkspace.shared.open(file.url)
    }

    func openDownloadsFolder() {
        NSWorkspace.shared.open(downloadDirectory)
    }

    // MARK: Known devices

    func isKnown(_ name: String) -> Bool {
        knownDevices.contains { $0.name == name }
    }

    /// Whether files from this sender should be accepted without asking.
    func autoAccepts(_ name: String) -> Bool {
        knownDevices.first { $0.name == name }?.autoAccept ?? false
    }

    /// Records a sender, optionally enabling auto-accept for it.
    func remember(_ name: String, autoAccept: Bool = false) {
        if let index = knownDevices.firstIndex(where: { $0.name == name }) {
            // Only ever turn auto-accept on here; never silently off.
            if autoAccept { knownDevices[index].autoAccept = true }
        } else {
            knownDevices.append(KnownDevice(name: name, autoAccept: autoAccept))
            knownDevices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        persistKnown()
    }

    func setAutoAccept(_ enabled: Bool, for name: String) {
        guard let index = knownDevices.firstIndex(where: { $0.name == name }) else { return }
        knownDevices[index].autoAccept = enabled
        persistKnown()
    }

    func forget(_ name: String) {
        knownDevices.removeAll { $0.name == name }
        persistKnown()
    }

    private func persistKnown() { prefs.save(knownDevices: knownDevices) }


    // MARK: Intents — Receive

    func toggleVisibility() {
        setVisible(!wantsVisible)
    }

    /// Records the intent immediately, then asks the engine.
    func setVisible(_ on: Bool) {
        wantsVisible = on
        visibilityFailed = false
        if on {
            service.startAdvertising(deviceName: deviceName)
            scheduleVisibilityTimeout()
        } else {
            service.stopAdvertising()
        }
    }

    private var visibilityToken = 0

    /// If advertising never comes up, don't leave a switch sitting on for
    /// something that isn't happening — turn it back off and say so.
    private func scheduleVisibilityTimeout() {
        visibilityToken += 1
        let token = visibilityToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, token == self.visibilityToken,
                  self.wantsVisible, !self.isVisible else { return }
            self.wantsVisible = false
            self.visibilityFailed = true
            self.service.stopAdvertising()
        }
    }

    /// Answers the pending request. `alwaysAccept` enables auto-accept for this
    /// sender from now on.
    func respondToIncoming(accept: Bool, alwaysAccept: Bool = false) {
        guard let req = incomingRequest else { return }
        if accept {
            remember(req.device.name, autoAccept: alwaysAccept)
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

    // Discovery is deliberately always on — it starts in `init` and runs until
    // quit, so the menu-bar device list is current whenever it's opened. There
    // are no start/stop intents because nothing should be turning it off.

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
        if isVisible {
            // It came up — cancel the pending failure check.
            //
            // Intent is deliberately NOT touched here. Setting it would let a
            // late "visible" arriving during teardown flip the switch back on
            // after the user has just turned it off.
            visibilityToken += 1
            visibilityFailed = false
        } else if wantsVisible {
            // Dropped out from under us; give it the same grace as a fresh start.
            scheduleVisibilityTimeout()
        }
    }

    func serviceDidReceiveIncomingRequest(_ request: IncomingRequest) {
        // `NSApp` is an implicitly-unwrapped global that is nil outside a running
        // GUI app. This path is driven by network input, so don't force it.
        if let app = NSApp { app.activate(ignoringOtherApps: true) }
        // Reopens the main window if it was closed — `NSApp.activate` alone
        // only reorders existing windows, it can't bring back a closed one.
        incomingActivityToken = UUID()

        if autoAccepts(request.device.name) {
            // Opted in for this sender: take it without interrupting, but
            // still surface the app — otherwise a transfer that needed no
            // confirmation was also the one case that never brought the
            // window forward, so it went unnoticed unless Receive already
            // happened to be the front tab.
            acceptIncoming(request)
            notifyAutoAccepted(request)
            return
        }
        incomingRequest = request   // surface the prompt
    }

    /// An auto-accepted transfer should still be visible to the user.
    private func notifyAutoAccepted(_ request: IncomingRequest) {
        // UNUserNotificationCenter.current() raises (not throws) unless the
        // process is a real .app — `swift run` and test hosts are not. The
        // transfer itself must not depend on being able to post a notification.
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }

        // Only Sendable values cross the concurrency boundary below; the
        // notification objects themselves are built where they're used.
        let id = request.id
        let title = "Receiving from \(request.device.name)"
        let body = request.summary

        // Ask at most once per launch. Requesting per transfer re-prompts
        // someone who already said no, every time a file arrives.
        switch notificationAuthorization {
        case .granted:
            postNotification(id: id, title: title, body: body)
        case .denied:
            return
        case .pending:
            // A request is already in flight; this transfer goes unannounced
            // rather than queueing a second prompt.
            return
        case .unknown:
            notificationAuthorization = .pending
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.notificationAuthorization = granted ? .granted : .denied
                    guard granted else { return }
                    self?.postNotification(id: id, title: title, body: body)
                }
            }
        }
    }

    /// Posts a notification. Called only once permission is known to be granted.
    private func postNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil))
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
            if error == nil {
                transfers[i].fraction = 1.0
                recordRecentFiles(from: transfers[i])
            }
        }
        if connection.device?.id == id { connection = .idle; stagedFiles = [] }
        finishCli(id, ok: error == nil, error: error)
    }

    func serviceDidResolveFiles(id: String, files: [TransferFile]) {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[i].files = files
    }
}
