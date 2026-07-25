import XCTest
import Network
import CryptoKit
import CommonCrypto
@testable import NearbyShareKit

/// Drives `decryptAndProcessReceivedSecureMessage` with frames a hostile peer
/// could send once the UKEY2 handshake has completed.
///
/// That matters because the handshake needs no user interaction: any device that
/// can reach the listening port while the Mac is visible gets to this layer
/// *before* the consent prompt appears.
final class MaliciousPayloadTests: XCTestCase {

    /// A connection with the session keys installed directly, so tests can skip
    /// the handshake and go straight at the frame handling.
    private func makeConnection() -> NearbyConnection {
        // Never started — we only exercise frame processing.
        let nw = NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
        let conn = NearbyConnection(connection: nw, id: "test")
        let key = [UInt8](repeating: 0x11, count: 32)
        conn.decryptKey = key
        conn.encryptKey = key
        conn.recvHmacKey = SymmetricKey(data: Data(repeating: 0x22, count: 32))
        conn.sendHmacKey = SymmetricKey(data: Data(repeating: 0x22, count: 32))
        return conn
    }

    /// Wrap an OfflineFrame the way a peer would: AES-256-CBC + HMAC-SHA256.
    private func secureMessage(wrapping offline: Location_Nearby_Connections_OfflineFrame,
                               sequence: Int32,
                               on conn: NearbyConnection) throws -> Securemessage_SecureMessage {
        var d2d = Securegcm_DeviceToDeviceMessage()
        d2d.sequenceNumber = sequence
        d2d.message = try offline.serializedData()
        let plaintext = [UInt8](try d2d.serializedData())

        let iv = Data.randomData(length: 16)
        var out = Data(count: plaintext.count + 16)
        var outLen = 0
        out.withUnsafeMutableBytes {
            let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128),
                                 CCOptions(kCCOptionPKCS7Padding),
                                 conn.encryptKey!, kCCKeySizeAES256, [UInt8](iv),
                                 plaintext, plaintext.count, $0.baseAddress, $0.count, &outLen)
            XCTAssertEqual(Int(status), kCCSuccess)
        }

        var hb = Securemessage_HeaderAndBody()
        hb.body = out.prefix(outLen)
        hb.header = Securemessage_Header()
        hb.header.encryptionScheme = .aes256Cbc
        hb.header.signatureScheme = .hmacSha256
        hb.header.iv = iv
        var md = Securegcm_GcmMetadata()
        md.type = .deviceToDeviceMessage
        md.version = 1
        hb.header.publicMetadata = try md.serializedData()

        var smsg = Securemessage_SecureMessage()
        smsg.headerAndBody = try hb.serializedData()
        smsg.signature = Data(HMAC<SHA256>.authenticationCode(for: smsg.headerAndBody,
                                                             using: conn.sendHmacKey!))
        return smsg
    }

    private func bytesPayload(id: Int64, totalSize: Int64, body: Data, offset: Int64 = 0,
                              lastChunk: Bool = false) -> Location_Nearby_Connections_OfflineFrame {
        var transfer = Location_Nearby_Connections_PayloadTransferFrame()
        transfer.packetType = .data
        transfer.payloadHeader.id = id
        transfer.payloadHeader.type = .bytes
        transfer.payloadHeader.totalSize = totalSize
        transfer.payloadHeader.isSensitive = false
        transfer.payloadChunk.offset = offset
        transfer.payloadChunk.flags = lastChunk ? 1 : 0
        transfer.payloadChunk.body = body

        var frame = Location_Nearby_Connections_OfflineFrame()
        frame.version = .v1
        frame.v1 = Location_Nearby_Connections_V1Frame()
        frame.v1.type = .payloadTransfer
        frame.v1.payloadTransfer = transfer
        return frame
    }

    /// Regression: a negative `totalSize` used to reach
    /// `NSMutableData(capacity:)`, which raises NSInvalidArgumentException
    /// ("absurd capacity") — an uncaught ObjC exception that kills the process.
    func testNegativeTotalSizeIsRejectedNotFatal() throws {
        for hostileSize in [Int64(-1), -4096, Int64(Int32.min), Int64.min] {
            let conn = makeConnection()
            let frame = bytesPayload(id: 1, totalSize: hostileSize, body: Data([0x01, 0x02]))
            let smsg = try secureMessage(wrapping: frame, sequence: 1, on: conn)

            XCTAssertThrowsError(try conn.decryptAndProcessReceivedSecureMessage(smsg),
                                 "totalSize \(hostileSize) must be rejected") { error in
                guard case NearbyError.protocolError = error else {
                    return XCTFail("expected a protocol error, got \(error)")
                }
            }
        }
    }

    func testOversizedTotalSizeIsStillRejected() throws {
        let conn = makeConnection()
        let frame = bytesPayload(id: 1, totalSize: 50 * 1024 * 1024, body: Data([0x01]))
        let smsg = try secureMessage(wrapping: frame, sequence: 1, on: conn)
        XCTAssertThrowsError(try conn.decryptAndProcessReceivedSecureMessage(smsg))
    }

    /// Regression: only individual frames were bounded, never the accumulated
    /// buffer, so well-formed sequential chunks could grow it without limit.
    func testAccumulatedPayloadCannotGrowUnbounded() throws {
        let conn = makeConnection()
        let chunk = Data(repeating: 0xAA, count: 512 * 1024)
        var offset: Int64 = 0
        var threw = false

        // Declare a small payload, then keep streaming far past it.
        for sequence in 1...40 {
            let frame = bytesPayload(id: 7, totalSize: 1024, body: chunk, offset: offset)
            let smsg = try secureMessage(wrapping: frame, sequence: Int32(sequence), on: conn)
            do {
                try conn.decryptAndProcessReceivedSecureMessage(smsg)
                offset += Int64(chunk.count)
            } catch {
                threw = true
                break
            }
        }
        XCTAssertTrue(threw, "streaming 20 MB into a 1 KB payload was accepted")
    }

    /// A hostile peer must not be able to pin memory by opening endless payloads.
    func testConcurrentPayloadBuffersAreCapped() throws {
        let conn = makeConnection()
        var threw = false
        for id in 1...(NearbyConnection.MAX_CONCURRENT_PAYLOADS + 8) {
            let frame = bytesPayload(id: Int64(id), totalSize: 4096,
                                     body: Data(repeating: 0xBB, count: 16))
            let smsg = try secureMessage(wrapping: frame, sequence: Int32(id), on: conn)
            do { try conn.decryptAndProcessReceivedSecureMessage(smsg) }
            catch { threw = true; break }
        }
        XCTAssertTrue(threw, "unbounded number of concurrent payload buffers accepted")
    }

    /// A tampered signature must be rejected before any decryption happens.
    func testForgedSignatureIsRejected() throws {
        let conn = makeConnection()
        let frame = bytesPayload(id: 1, totalSize: 16, body: Data([0x01]))
        var smsg = try secureMessage(wrapping: frame, sequence: 1, on: conn)
        smsg.signature = Data(repeating: 0x00, count: 32)
        XCTAssertThrowsError(try conn.decryptAndProcessReceivedSecureMessage(smsg))
    }
}
