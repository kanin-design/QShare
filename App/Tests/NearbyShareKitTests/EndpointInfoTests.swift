import XCTest
@testable import NearbyShareKit

/// `EndpointInfo(data:)` decodes an unauthenticated blob straight off the
/// network (the mDNS TXT `n=` record). It must reject junk rather than crash,
/// over-read, or spin.
final class EndpointInfoTests: XCTestCase {

    /// Well-formed: flags byte, 16 filler bytes, name length, name.
    private func encode(name: String, deviceType: UInt8 = 3) -> Data {
        var bytes: [UInt8] = [deviceType << 1]
        bytes.append(contentsOf: [UInt8](repeating: 0xAB, count: 16))
        let nameBytes = [UInt8](name.utf8)
        bytes.append(UInt8(nameBytes.count))
        bytes.append(contentsOf: nameBytes)
        return Data(bytes)
    }

    func testRoundTripsAWellFormedRecord() throws {
        let info = try XCTUnwrap(EndpointInfo(data: encode(name: "Pixel 8 Pro")))
        XCTAssertEqual(info.name, "Pixel 8 Pro")
        XCTAssertEqual(info.deviceType, .computer)
    }

    func testSerializeParseRoundTrip() throws {
        let original = EndpointInfo(name: "Test Mac", deviceType: .computer)
        let parsed = try XCTUnwrap(EndpointInfo(data: original.serialize()))
        XCTAssertEqual(parsed.name, "Test Mac")
        XCTAssertEqual(parsed.deviceType, .computer)
    }

    func testTruncatedRecordsAreRejected() {
        for length in 0...17 {
            XCTAssertNil(EndpointInfo(data: Data(repeating: 0, count: length)),
                         "accepted a \(length)-byte record")
        }
    }

    func testNameLengthLongerThanBufferIsRejected() {
        var bytes = [UInt8](repeating: 0, count: 18)
        bytes[17] = 200                      // claims 200 bytes of name…
        bytes.append(contentsOf: [1, 2, 3])  // …but only 3 follow
        XCTAssertNil(EndpointInfo(data: Data(bytes)))
    }

    func testInvalidUTF8NameIsRejected() {
        var bytes: [UInt8] = [0x06]
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 16))
        bytes.append(2)
        bytes.append(contentsOf: [0xFF, 0xFE])   // not valid UTF-8
        XCTAssertNil(EndpointInfo(data: Data(bytes)))
    }

    /// The 0x10 flag means "no name". Parsing must succeed with a nil name —
    /// callers are responsible for not force-unwrapping it.
    func testNamelessRecordParsesWithNilName() throws {
        var bytes: [UInt8] = [0x10]
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 17))
        let info = try XCTUnwrap(EndpointInfo(data: Data(bytes)))
        XCTAssertNil(info.name)
    }

    /// A malformed TLV tail must not loop forever. The decoder advances by the
    /// 2-byte header even when it refuses the payload; this pins that down.
    func testMalformedTLVTailTerminates() {
        let expectation = expectation(description: "decoder returns")
        DispatchQueue.global().async {
            var bytes = [UInt8](self.encode(name: "x"))
            // Records whose declared length always overruns the buffer.
            for _ in 0..<64 { bytes.append(contentsOf: [1, 0xFF]) }
            _ = EndpointInfo(data: Data(bytes))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    /// Random junk must never trap.
    func testRandomInputNeverCrashes() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2_000 {
            let count = Int.random(in: 0...300, using: &rng)
            let bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &rng) }
            _ = EndpointInfo(data: Data(bytes))   // must simply return
        }
    }
}
