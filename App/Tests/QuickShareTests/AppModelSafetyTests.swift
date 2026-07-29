import XCTest
@testable import QuickShare

/// A service double that records what the model asked the engine to do.
@MainActor
final class SpyService: QuickShareService {
    weak var delegate: QuickShareServiceDelegate?

    private(set) var consentResponses: [(id: String, accept: Bool)] = []
    private(set) var sentFiles: [(files: [FileItem], device: RemoteDevice)] = []
    private(set) var advertising = false

    func startAdvertising(deviceName: String) { advertising = true }
    func stopAdvertising() { advertising = false }
    func respondToIncoming(id: String, accept: Bool) { consentResponses.append((id, accept)) }
    func setReceiveDirectory(_ url: URL) {}
    func startDiscovery() {}
    func stopDiscovery() {}
    func sendFiles(_ files: [FileItem], to device: RemoteDevice) { sentFiles.append((files, device)) }
    func cancelTransfer(id: String) {}
    func prepareQRCode() -> String? { "qr" }
    func cancelQRCode() {}
}

@MainActor
final class AppModelSafetyTests: XCTestCase {

    private var spy: SpyService!
    private var model: AppModel!

    override func setUp() async throws {
        try await super.setUp()
        // AppModel persists to UserDefaults.standard; start from a clean slate so
        // tests don't inherit each other's (or the real app's) state.
        for key in ["knownDevices", "knownDeviceNames", "trustedDeviceNames", "controlAPIEnabled",
                    "startVisible", "downloadDirectoryPath", "appearance"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        spy = SpyService()
        model = AppModel(service: spy)
    }

    override func tearDown() async throws {
        for key in ["knownDevices", "knownDeviceNames", "trustedDeviceNames", "controlAPIEnabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try await super.tearDown()
    }

    private func request(from name: String, id: String = "t1") -> IncomingRequest {
        IncomingRequest(id: id,
                        device: RemoteDevice(id: "d-\(name)", name: name, type: .phone),
                        fileNames: ["photo.jpg"], totalBytes: 1234, pin: "1234")
    }

    // MARK: Auto-accept is per-device and opt-in

    /// Being known is not consent. A sender you've accepted from once must still
    /// prompt until you explicitly enable auto-accept for it.
    func testKnownButNotAutoAcceptedStillPrompts() {
        model.remember("Pixel 8 Pro")
        XCTAssertTrue(model.isKnown("Pixel 8 Pro"))
        XCTAssertFalse(model.autoAccepts("Pixel 8 Pro"))

        model.serviceDidReceiveIncomingRequest(request(from: "Pixel 8 Pro"))

        XCTAssertEqual(model.incomingRequest?.device.name, "Pixel 8 Pro")
        XCTAssertTrue(spy.consentResponses.isEmpty,
                      "nothing may be accepted before the user answers")
        XCTAssertTrue(model.transfers.isEmpty)
    }

    /// Once enabled, that sender is accepted without a prompt.
    func testAutoAcceptEnabledSkipsThePrompt() {
        model.remember("Pixel 8 Pro", autoAccept: true)

        model.serviceDidReceiveIncomingRequest(request(from: "Pixel 8 Pro"))

        XCTAssertNil(model.incomingRequest, "an auto-accepted sender must not prompt")
        XCTAssertEqual(spy.consentResponses.map(\.accept), [true])
        XCTAssertEqual(model.transfers.count, 1)
        XCTAssertEqual(model.transfers.first?.direction, .incoming)
    }

    /// Auto-accept is scoped to the device it was enabled for.
    func testAutoAcceptDoesNotLeakToOtherSenders() {
        model.remember("Pixel 8 Pro", autoAccept: true)

        model.serviceDidReceiveIncomingRequest(request(from: "Someone Else"))

        XCTAssertNotNil(model.incomingRequest)
        XCTAssertTrue(spy.consentResponses.isEmpty)
    }

    func testUnknownDevicePrompts() {
        model.serviceDidReceiveIncomingRequest(request(from: "Stranger"))
        XCTAssertNotNil(model.incomingRequest)
        XCTAssertTrue(spy.consentResponses.isEmpty)
    }

    func testTogglingAutoAcceptOffRestoresThePrompt() {
        model.remember("Tablet", autoAccept: true)
        model.setAutoAccept(false, for: "Tablet")

        model.serviceDidReceiveIncomingRequest(request(from: "Tablet"))
        XCTAssertNotNil(model.incomingRequest)
    }

    /// An upgrade must never silently switch auto-accept on: the older lists
    /// carried no per-device choice, so the safe reading is "ask".
    func testMigratedListsArriveWithAutoAcceptOff() {
        UserDefaults.standard.set(["Old Phone"], forKey: "trustedDeviceNames")
        UserDefaults.standard.set(["Older Phone"], forKey: "knownDeviceNames")
        let fresh = AppModel(service: SpyService())

        XCTAssertTrue(fresh.isKnown("Old Phone"))
        XCTAssertTrue(fresh.isKnown("Older Phone"))
        XCTAssertFalse(fresh.autoAccepts("Old Phone"), "migration must not enable auto-accept")
        XCTAssertFalse(fresh.autoAccepts("Older Phone"), "migration must not enable auto-accept")

        XCTAssertNil(UserDefaults.standard.stringArray(forKey: "trustedDeviceNames"),
                     "legacy key should be cleared")
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: "knownDeviceNames"),
                     "legacy key should be cleared")
    }

    // MARK: Consent bookkeeping

    func testAcceptingRecordsTheSender() {
        model.serviceDidReceiveIncomingRequest(request(from: "Galaxy S24"))
        model.respondToIncoming(accept: true)

        XCTAssertEqual(spy.consentResponses.map(\.accept), [true])
        XCTAssertTrue(model.isKnown("Galaxy S24"))
        XCTAssertFalse(model.autoAccepts("Galaxy S24"),
                       "a plain accept must not enable auto-accept")
        XCTAssertEqual(model.transfers.count, 1)
        XCTAssertNil(model.incomingRequest)
    }

    /// Ticking "always accept" on the prompt enables it for that sender.
    func testAcceptingWithAlwaysEnablesAutoAccept() {
        model.serviceDidReceiveIncomingRequest(request(from: "Galaxy S24"))
        model.respondToIncoming(accept: true, alwaysAccept: true)

        XCTAssertTrue(model.autoAccepts("Galaxy S24"))

        // The next transfer from that name goes straight through.
        model.serviceDidReceiveIncomingRequest(request(from: "Galaxy S24", id: "t2"))
        XCTAssertNil(model.incomingRequest)
        XCTAssertEqual(spy.consentResponses.map(\.accept), [true, true])
    }

    func testDecliningDoesNotRecordOrStartATransfer() {
        model.serviceDidReceiveIncomingRequest(request(from: "Galaxy S24"))
        model.respondToIncoming(accept: false)

        XCTAssertEqual(spy.consentResponses.map(\.accept), [false])
        XCTAssertFalse(model.isKnown("Galaxy S24"))
        XCTAssertTrue(model.transfers.isEmpty)
        XCTAssertNil(model.incomingRequest)
    }

    func testForgettingRemovesTheSender() {
        model.remember("Tablet", autoAccept: true)
        model.forget("Tablet")
        XCTAssertFalse(model.isKnown("Tablet"))
        XCTAssertFalse(model.autoAccepts("Tablet"))
    }

    func testRememberIsIdempotentAndNeverDowngrades() {
        model.remember("Phone", autoAccept: true)
        model.remember("Phone")   // a later plain accept must not turn it off
        XCTAssertEqual(model.knownDevices.filter { $0.name == "Phone" }.count, 1)
        XCTAssertTrue(model.autoAccepts("Phone"))
    }

    func testKnownDevicesPersistAcrossLaunches() {
        model.remember("Persisted", autoAccept: true)
        let fresh = AppModel(service: SpyService())
        XCTAssertTrue(fresh.isKnown("Persisted"))
        XCTAssertTrue(fresh.autoAccepts("Persisted"))
    }

    // MARK: CLI must not hijack the window's send flow

    func testCliSendIsRefusedWhileTheUserIsMidFlow() {
        let device = RemoteDevice(id: "d1", name: "Pixel", type: .phone)
        model.serviceDidDiscover(device)
        model.selectDevice(device)                       // user is staging
        model.stage(urls: [URL(fileURLWithPath: "/tmp/a.txt")])
        let staged = model.stagedFiles

        var result: AppModel.CliSendResult?
        model.cliSend(paths: ["/etc/hosts"], to: "Pixel") { result = $0 }

        XCTAssertEqual(result?.error, "busy")
        XCTAssertEqual(result?.ok, false)
        XCTAssertEqual(model.stagedFiles.map(\.url), staged.map(\.url),
                       "the user's staged files must be untouched")
        XCTAssertTrue(spy.sentFiles.isEmpty)
    }

    func testCliSendReportsUnknownDevice() {
        var result: AppModel.CliSendResult?
        model.cliSend(paths: ["/etc/hosts"], to: "Nope") { result = $0 }
        XCTAssertEqual(result?.error, "device_not_found")
    }

    func testCliSendRejectsUnreadablePaths() {
        let device = RemoteDevice(id: "d1", name: "Pixel", type: .phone)
        model.serviceDidDiscover(device)
        var result: AppModel.CliSendResult?
        model.cliSend(paths: ["/no/such/file/anywhere"], to: "Pixel") { result = $0 }
        XCTAssertEqual(result?.error, "no_readable_files")
    }

    // MARK: Device list ordering

    func testAvailableDevicesPutsKnownFirstAndIsStable() {
        for name in ["Zeta", "Alpha", "Mid"] {
            model.serviceDidDiscover(RemoteDevice(id: "d-\(name)", name: name, type: .phone))
        }
        model.remember("Mid")

        let order = model.availableDevices.map(\.name)
        XCTAssertEqual(order.first, "Mid", "known devices sort first")
        XCTAssertEqual(order, ["Mid", "Alpha", "Zeta"], "ties sort by name, not arbitrarily")
        XCTAssertEqual(model.availableDevices.map(\.name), order, "ordering is stable across reads")
    }

    // MARK: Visibility reflects the engine, never the request

    /// The switch follows intent so it responds instantly; the reported status
    /// follows the engine so it never claims more than is true.
    func testIntentIsImmediateButStatusWaitsForTheEngine() {
        XCTAssertEqual(model.visibilityStatus, .off)

        model.toggleVisibility()
        XCTAssertTrue(model.wantsVisible, "the switch must move immediately")
        XCTAssertTrue(spy.advertising, "the engine was asked to advertise")
        XCTAssertFalse(model.isVisible, "nothing is published yet")
        XCTAssertEqual(model.visibilityStatus, .starting)

        model.serviceDidUpdateVisibility(isVisible: true)
        XCTAssertTrue(model.isVisible)
        XCTAssertEqual(model.visibilityStatus, .on)
    }

    func testTurningOffIsAlsoImmediate() {
        model.setVisible(true)
        model.serviceDidUpdateVisibility(isVisible: true)
        XCTAssertEqual(model.visibilityStatus, .on)

        model.setVisible(false)
        XCTAssertFalse(model.wantsVisible, "the switch must move immediately")
        XCTAssertFalse(spy.advertising, "the engine was asked to stop")
        // Still published until the engine confirms it tore down.
        XCTAssertEqual(model.visibilityStatus, .stopping)

        model.serviceDidUpdateVisibility(isVisible: false)
        XCTAssertEqual(model.visibilityStatus, .off)
    }

    /// Advertising dropping out on its own must show as pending again, not as on.
    func testLosingAdvertisingReturnsToStarting() {
        model.setVisible(true)
        model.serviceDidUpdateVisibility(isVisible: true)
        model.serviceDidUpdateVisibility(isVisible: false)

        XCTAssertTrue(model.wantsVisible, "the user still wants to be visible")
        XCTAssertEqual(model.visibilityStatus, .starting)
    }

    // MARK: Control API default

    func testControlAPIIsOffByDefault() {
        XCTAssertFalse(model.controlAPIEnabled)
    }

    func testControlAPITogglePersists() {
        model.setControlAPIEnabled(true)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "controlAPIEnabled"))
        model.setControlAPIEnabled(false)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "controlAPIEnabled"))
    }
}
