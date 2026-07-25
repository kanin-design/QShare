import XCTest
import SwiftProtobuf
@testable import NearbyShareKit

/// Not a test — a one-shot generator. Uses swift-protobuf as an ORACLE to emit
/// golden wire bytes for every message the protocol actually uses. The
/// hand-written codec is then asserted byte-exact against these, which is how we
/// prove wire compatibility after the dependency is gone.
///
/// Run with: swift test --filter GenerateGoldenFixtures
final class GenerateGoldenFixtures: XCTestCase {

    private var out: [(String, String)] = []

    private func capture<M: SwiftProtobuf.Message>(_ name: String, _ msg: M) throws {
        out.append((name, try msg.serializedData().base64EncodedString()))
    }

    func testGenerate() throws {
        // --- securemessage ---
        var ecKey = Securemessage_EcP256PublicKey()
        ecKey.x = Data((1...32).map { UInt8($0) })
        ecKey.y = Data((33...64).map { UInt8($0) })
        try capture("EcP256PublicKey", ecKey)

        var generic = Securemessage_GenericPublicKey()
        generic.type = .ecP256
        generic.ecP256PublicKey = ecKey
        try capture("GenericPublicKey", generic)

        var gcmMeta = Securegcm_GcmMetadata()
        gcmMeta.type = .deviceToDeviceMessage
        gcmMeta.version = 1
        try capture("GcmMetadata", gcmMeta)

        var header = Securemessage_Header()
        header.encryptionScheme = .aes256Cbc
        header.signatureScheme = .hmacSha256
        header.iv = Data((0..<16).map { UInt8($0) })
        header.publicMetadata = try gcmMeta.serializedData()
        try capture("Header", header)

        var hb = Securemessage_HeaderAndBody()
        hb.header = header
        hb.body = Data(repeating: 0xAB, count: 48)
        try capture("HeaderAndBody", hb)

        var smsg = Securemessage_SecureMessage()
        smsg.headerAndBody = try hb.serializedData()
        smsg.signature = Data(repeating: 0xCD, count: 32)
        try capture("SecureMessage", smsg)

        // --- device to device ---
        var d2d = Securegcm_DeviceToDeviceMessage()
        d2d.sequenceNumber = 7
        d2d.message = Data(repeating: 0x11, count: 20)
        try capture("DeviceToDeviceMessage", d2d)

        // --- ukey2 ---
        var commitment = Securegcm_Ukey2ClientInit.CipherCommitment()
        commitment.handshakeCipher = .p256Sha512
        commitment.commitment = Data(repeating: 0x22, count: 32)
        try capture("CipherCommitment", commitment)

        var clientInit = Securegcm_Ukey2ClientInit()
        clientInit.version = 1
        clientInit.random = Data(repeating: 0x33, count: 32)
        clientInit.nextProtocol = "AES_256_CBC-HMAC_SHA256"
        clientInit.cipherCommitments = [commitment]
        try capture("Ukey2ClientInit", clientInit)

        var serverInit = Securegcm_Ukey2ServerInit()
        serverInit.version = 1
        serverInit.random = Data(repeating: 0x44, count: 32)
        serverInit.handshakeCipher = .p256Sha512
        serverInit.publicKey = try generic.serializedData()
        try capture("Ukey2ServerInit", serverInit)

        var clientFinish = Securegcm_Ukey2ClientFinished()
        clientFinish.publicKey = try generic.serializedData()
        try capture("Ukey2ClientFinished", clientFinish)

        var alert = Securegcm_Ukey2Alert()
        alert.type = .badMessageType
        try capture("Ukey2Alert", alert)

        var ukeyMsg = Securegcm_Ukey2Message()
        ukeyMsg.messageType = .clientInit
        ukeyMsg.messageData = try clientInit.serializedData()
        try capture("Ukey2Message", ukeyMsg)

        // --- offline wire format ---
        var osInfo = Location_Nearby_Connections_OsInfo()
        osInfo.type = .apple
        try capture("OsInfo", osInfo)

        var connReq = Location_Nearby_Connections_ConnectionRequestFrame()
        connReq.endpointID = "ABCD"
        connReq.endpointName = "Test Mac"
        connReq.endpointInfo = Data(repeating: 0x55, count: 20)
        try capture("ConnectionRequestFrame", connReq)

        var connResp = Location_Nearby_Connections_ConnectionResponseFrame()
        connResp.response = .accept
        connResp.status = 0
        connResp.osInfo = osInfo
        try capture("ConnectionResponseFrame", connResp)

        var payload = Location_Nearby_Connections_PayloadTransferFrame()
        payload.packetType = .data
        payload.payloadHeader.id = 1234567890
        payload.payloadHeader.type = .bytes
        payload.payloadHeader.totalSize = 512
        payload.payloadHeader.isSensitive = false
        payload.payloadChunk.offset = 0
        payload.payloadChunk.flags = 1
        payload.payloadChunk.body = Data(repeating: 0x66, count: 32)
        try capture("PayloadTransferFrame", payload)

        var fileHeader = Location_Nearby_Connections_PayloadTransferFrame()
        fileHeader.packetType = .data
        fileHeader.payloadHeader.id = -98765
        fileHeader.payloadHeader.type = .file
        fileHeader.payloadHeader.totalSize = 9_000_000
        fileHeader.payloadChunk.offset = 4096
        fileHeader.payloadChunk.flags = 0
        try capture("PayloadTransferFrameFile", fileHeader)

        var offline = Location_Nearby_Connections_OfflineFrame()
        offline.version = .v1
        offline.v1.type = .payloadTransfer
        offline.v1.payloadTransfer = payload
        try capture("OfflineFramePayload", offline)

        var offlineKeepAlive = Location_Nearby_Connections_OfflineFrame()
        offlineKeepAlive.version = .v1
        offlineKeepAlive.v1.type = .keepAlive
        offlineKeepAlive.v1.keepAlive.ack = true
        try capture("OfflineFrameKeepAlive", offlineKeepAlive)

        var offlineReq = Location_Nearby_Connections_OfflineFrame()
        offlineReq.version = .v1
        offlineReq.v1.type = .connectionRequest
        offlineReq.v1.connectionRequest = connReq
        try capture("OfflineFrameConnectionRequest", offlineReq)

        var offlineResp = Location_Nearby_Connections_OfflineFrame()
        offlineResp.version = .v1
        offlineResp.v1.type = .connectionResponse
        offlineResp.v1.connectionResponse = connResp
        try capture("OfflineFrameConnectionResponse", offlineResp)

        var offlineDisc = Location_Nearby_Connections_OfflineFrame()
        offlineDisc.version = .v1
        offlineDisc.v1.type = .disconnection
        offlineDisc.v1.disconnection = Location_Nearby_Connections_DisconnectionFrame()
        try capture("OfflineFrameDisconnection", offlineDisc)

        // --- sharing frames ---
        var fileMeta = Sharing_Nearby_FileMetadata()
        fileMeta.name = "photo.jpg"
        fileMeta.type = .image
        fileMeta.payloadID = 42
        fileMeta.size = 123456
        fileMeta.mimeType = "image/jpeg"
        fileMeta.id = 9
        try capture("FileMetadata", fileMeta)

        var textMeta = Sharing_Nearby_TextMetadata()
        textMeta.textTitle = "a link"
        textMeta.type = .url
        textMeta.payloadID = 77
        textMeta.size = 20
        textMeta.id = 3
        try capture("TextMetadata", textMeta)

        var intro = Sharing_Nearby_IntroductionFrame()
        intro.fileMetadata = [fileMeta]
        intro.textMetadata = [textMeta]
        try capture("IntroductionFrame", intro)

        var pairedEnc = Sharing_Nearby_PairedKeyEncryptionFrame()
        pairedEnc.secretIDHash = Data(repeating: 0x77, count: 6)
        pairedEnc.signedData = Data(repeating: 0x88, count: 72)
        try capture("PairedKeyEncryptionFrame", pairedEnc)

        var pairedRes = Sharing_Nearby_PairedKeyResultFrame()
        pairedRes.status = .unable
        try capture("PairedKeyResultFrame", pairedRes)

        var sharingResp = Sharing_Nearby_ConnectionResponseFrame()
        sharingResp.status = .accept
        try capture("SharingConnectionResponseFrame", sharingResp)

        var sharingFrame = Sharing_Nearby_Frame()
        sharingFrame.version = .v1
        sharingFrame.v1.type = .introduction
        sharingFrame.v1.introduction = intro
        try capture("SharingFrameIntroduction", sharingFrame)

        var sharingCancel = Sharing_Nearby_Frame()
        sharingCancel.version = .v1
        sharingCancel.v1.type = .cancel
        try capture("SharingFrameCancel", sharingCancel)

        var sharingPaired = Sharing_Nearby_Frame()
        sharingPaired.version = .v1
        sharingPaired.v1.type = .pairedKeyEncryption
        sharingPaired.v1.pairedKeyEncryption = pairedEnc
        try capture("SharingFramePairedKeyEncryption", sharingPaired)

        var sharingResult = Sharing_Nearby_Frame()
        sharingResult.version = .v1
        sharingResult.v1.type = .pairedKeyResult
        sharingResult.v1.pairedKeyResult = pairedRes
        try capture("SharingFramePairedKeyResult", sharingResult)

        var sharingRespFrame = Sharing_Nearby_Frame()
        sharingRespFrame.version = .v1
        sharingRespFrame.v1.type = .response
        sharingRespFrame.v1.connectionResponse = sharingResp
        try capture("SharingFrameResponse", sharingRespFrame)

        // Emit a Swift source file of fixtures into the new test target.
        var src = """
        // GENERATED — golden wire bytes captured from apple/swift-protobuf before
        // that dependency was removed. They pin the hand-written codec to the exact
        // bytes the reference implementation produced. Do not edit by hand.
        //
        // Regenerate only if the protocol itself changes, and only by restoring
        // swift-protobuf temporarily.

        enum GoldenFixtures {
            static let all: [String: String] = [

        """
        for (name, b64) in out.sorted(by: { $0.0 < $1.0 }) {
            src += "        \"\(name)\": \"\(b64)\",\n"
        }
        src += "    ]\n}\n"

        let dest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuickShareProtocolTests/GoldenFixtures.swift")
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try src.write(to: dest, atomically: true, encoding: .utf8)
        print("WROTE \(out.count) fixtures -> \(dest.path)")
    }
}
