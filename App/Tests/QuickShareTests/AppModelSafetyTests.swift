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
        for key in ["knownDeviceNames", "trustedDeviceNames", "controlAPIEnabled",
                    "startVisible", "downloadDirectoryPath", "appearance"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        spy = SpyService()
        model = AppModel(service: spy)
    }

    override func tearDown() async throws {
        for key in ["knownDeviceNames", "trustedDeviceNames", "controlAPIEnabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try await super.tearDown()
    }

    private func request(from name: String, id: String = "t1") -> IncomingRequest {
        IncomingRequest(id: id,
                        device: RemoteDevice(id: "d-\(name)", name: name, type: .phone),
                        fileNames: ["photo.jpg"], totalBytes: 1234, pin: "1234")
    }

    // MARK: The vulnerability this suite exists to prevent

    /// Regression: a device name previously accepted from must NOT cause a
    /// silent auto-accept. Names are remote-supplied and unauthenticated, so
    /// anything on the LAN could claim one.
    func testKnownDeviceNameDoesNotAutoAccept() {
        model.remember("Pixel 8 Pro")
        XCTAssertTrue(model.isKnown("Pixel 8 Pro"))

        model.serviceDidReceiveIncomingRequest(request(from: "Pixel 8 Pro"))

        XCTAssertEqual(model.incomingRequest?.device.name, "Pixel 8 Pro",
                       "a known name must still raise the prompt")
        XCTAssertTrue(spy.consentResponses.isEmpty,
                      "nothing may be accepted before the user answers")
        XCTAssertTrue(model.transfers.isEmpty,
                      "no transfer may start before the user answers")
    }

    func testUnknownDeviceAlsoPrompts() {
        model.serviceDidReceiveIncomingRequest(request(from: "Stranger"))
        XCTAssertNotNil(model.incomingRequest)
        XCTAssertTrue(spy.consentResponses.isEmpty)
    }

    /// The legacy auto-accept list must not survive an upgrade.
    func testLegacyTrustListIsMigratedAndCleared() {
        UserDefaults.standard.set(["Old Phone"], forKey: "trustedDeviceNames")
        let fresh = AppModel(service: SpyService())

        XCTAssertNil(UserDefaults.standard.stringArray(forKey: "trustedDeviceNames"),
                     "the old auto-accept key must be removed")
        XCTAssertTrue(fresh.isKnown("Old Phone"), "the name is kept as a hint")

        fresh.serviceDidReceiveIncomingRequest(request(from: "Old Phone"))
        XCTAssertNotNil(fresh.incomingRequest, "migrated names must not auto-accept")
    }

    // MARK: Consent bookkeeping

    func testAcceptingRecordsTheNameAndStartsTheTransfer() {
        model.serviceDidReceiveIncomingRequest(request(from: "Galaxy S24"))
        model.respondToIncoming(accept: true)

        XCTAssertEqual(spy.consentResponses.map(\.accept), [true])
        XCTAssertTrue(model.isKnown("Galaxy S24"))
        XCTAssertEqual(model.transfers.count, 1)
        XCTAssertEqual(model.transfers.first?.direction, .incoming)
        XCTAssertNil(model.incomingRequest)
    }

    func testDecliningDoesNotRecordOrStartATransfer() {
        model.serviceDidReceiveIncomingRequest(request(from: "Galaxy S24"))
        model.respondToIncoming(accept: false)

        XCTAssertEqual(spy.consentResponses.map(\.accept), [false])
        XCTAssertFalse(model.isKnown("Galaxy S24"))
        XCTAssertTrue(model.transfers.isEmpty)
        XCTAssertNil(model.incomingRequest)
    }

    func testForgettingRemovesTheHint() {
        model.remember("Tablet")
        model.forget("Tablet")
        XCTAssertFalse(model.isKnown("Tablet"))
    }

    func testRememberIsIdempotent() {
        model.remember("Phone")
        model.remember("Phone")
        XCTAssertEqual(model.knownDevices.filter { $0 == "Phone" }.count, 1)
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

    func testVisibilityOnlyFollowsEngineCallbacks() {
        XCTAssertFalse(model.isVisible)
        model.toggleVisibility()
        XCTAssertTrue(spy.advertising, "the engine was asked to advertise")
        XCTAssertFalse(model.isVisible,
                       "the switch must not flip until the engine confirms")

        model.serviceDidUpdateVisibility(isVisible: true)
        XCTAssertTrue(model.isVisible)

        // Engine reports advertising failed/stopped out from under us.
        model.serviceDidUpdateVisibility(isVisible: false)
        XCTAssertFalse(model.isVisible)
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
