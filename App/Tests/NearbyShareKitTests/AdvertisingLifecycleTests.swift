import XCTest
import Foundation
@testable import NearbyShareKit

/// Integration coverage for the visibility lifecycle. This is deliberately not a
/// pure unit test: it starts a real `NWListener` and publishes a real Bonjour
/// service, because the failures worth catching here only happen at that seam.
///
/// It exists because a plausible-looking refactor broke advertising in a way no
/// unit test could see: `initMDNS()` runs from the listener's state handler on a
/// dispatch queue with no run loop, so `NetService` delegate callbacks never
/// fired and the app would have shown "not visible" forever while actually
/// being visible.
final class AdvertisingLifecycleTests: XCTestCase, MainAppDelegate {

    private var transitions: [Bool] = []
    private var becameVisible: XCTestExpectation?
    private let lock = NSLock()

    // MainAppDelegate — only visibility matters here.
    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {}
    func incomingTransfer(id: String, didFinishWith error: Error?) {}
    func visibilityDidChange(isVisible: Bool) {
        lock.lock()
        transitions.append(isVisible)
        lock.unlock()
        if isVisible { becameVisible?.fulfill() }
    }

    private var lastTransition: Bool? {
        lock.lock(); defer { lock.unlock() }
        return transitions.last
    }

    override func tearDown() async throws {
        NearbyConnectionManager.shared.becomeInvisible()
        NearbyConnectionManager.shared.mainAppDelegate = nil
        try await super.tearDown()
    }

    /// `becomeVisible()` must actually publish, and must say so.
    func testBecomeVisibleReportsVisibleOnlyAfterPublishing() {
        let manager = NearbyConnectionManager.shared
        manager.mainAppDelegate = self

        becameVisible = expectation(description: "published")
        manager.becomeVisible()
        wait(for: [becameVisible!], timeout: 30)

        XCTAssertEqual(lastTransition, true)
    }

    /// The off→on race: `NWListener.cancel()` is asynchronous, so going invisible
    /// and immediately visible again used to restart a cancelling listener.
    func testRapidOffThenOnReAdvertises() {
        let manager = NearbyConnectionManager.shared
        manager.mainAppDelegate = self

        becameVisible = expectation(description: "first publish")
        manager.becomeVisible()
        wait(for: [becameVisible!], timeout: 30)

        manager.becomeInvisible()
        becameVisible = expectation(description: "republish")
        manager.becomeVisible()   // immediately, while cancel() is still in flight
        wait(for: [becameVisible!], timeout: 30)

        XCTAssertEqual(lastTransition, true, "toggling off then straight back on must re-advertise")
    }

    /// Repeated `becomeVisible()` must not start an already-started listener.
    func testRepeatedBecomeVisibleIsIdempotent() {
        let manager = NearbyConnectionManager.shared
        manager.mainAppDelegate = self

        becameVisible = expectation(description: "published")
        manager.becomeVisible()
        manager.becomeVisible()
        manager.becomeVisible()
        wait(for: [becameVisible!], timeout: 30)

        lock.lock()
        let visibleReports = transitions.filter { $0 }.count
        lock.unlock()
        XCTAssertEqual(visibleReports, 1, "visibility should be reported once, not per call")
    }
}
