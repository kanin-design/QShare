import Foundation
import Network
import CryptoKit
import UniformTypeIdentifiers

/// Sends a transfer: performs the UKEY2 handshake as the client, offers the
/// files, and streams them once the remote user accepts.
public actor OutboundSession {

    /// How much file data goes in one chunk.
    private static let chunkSize = 512 * 1024

    public let id: String
    private let channel: FrameChannel
    private let files: [OutgoingFile]
    private let localName: String
    private let localEndpointID: String

    private var secure: SecureChannel?
    private var continuation: AsyncStream<OutboundEvent>.Continuation?
    private var finished = false
    private var cancelled = false

    private var totalBytes: Int64 = 0
    private var sentBytes: Int64 = 0
    private var payloadIDs: [Int64] = []

    public init(connection: NWConnection, id: String, files: [OutgoingFile],
                localName: String, localEndpointID: String) {
        self.id = id
        self.channel = FrameChannel(connection: connection)
        self.files = files
        self.localName = localName
        self.localEndpointID = localEndpointID
    }

    public func events() -> AsyncStream<OutboundEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            Task { await self.run() }
        }
    }

    public func cancel() async {
        cancelled = true
        if let secure {
            try? await secure.sendSetupFrame(.cancel())
            try? await secure.sendDisconnect()
        }
        await finish(.failed(.rejected(.userCanceled)))
    }

    // MARK: Main flow

    private func run() async {
        do {
            try await channel.start()
            let keys = try await performHandshake()
            continuation?.yield(.connected(pinCode: keys.pinCode))
            try await exchangeSetupFrames()
            try await sendIntroductionAndAwaitConsent()
            try await sendFiles()
        } catch let error as QuickShareError {
            await finish(.failed(error))
        } catch {
            await finish(.failed(.localFailure(error.localizedDescription)))
        }
    }

    private func performHandshake() async throws -> UKey2.SessionKeys {
        // 1. ConnectionRequest.
        var request = ConnectionRequestFrame()
        request.endpointID = localEndpointID
        request.endpointName = localName
        request.endpointInfo = EndpointInfo(name: localName, deviceType: .computer).serialized()
        var v1 = V1Frame()
        v1.type = .connectionRequest
        v1.connectionRequest = request
        try await channel.send(frame: OfflineFrame.wrapping(v1).serialized())

        // 2. Ukey2ClientInit. The commitment is SHA-512 over the *exact* bytes of
        // the ClientFinished we will send later, so build that first.
        let keyPair = UKey2.KeyPair()
        let clientFinished: Ukey2ClientFinished = {
            var f = Ukey2ClientFinished()
            f.publicKey = keyPair.genericPublicKey.serialized()
            return f
        }()
        let clientFinishedBytes = Ukey2Message(type: .clientFinish,
                                               data: clientFinished.serialized()).serialized()

        var commitment = Ukey2CipherCommitment()
        commitment.handshakeCipher = .p256Sha512
        commitment.commitment = Data(SHA512.hash(data: clientFinishedBytes))

        var clientInit = Ukey2ClientInit()
        clientInit.version = 1
        clientInit.random = Data.secureRandom(count: 32)
        clientInit.nextProtocol = "AES_256_CBC-HMAC_SHA256"
        clientInit.cipherCommitments = [commitment]
        let clientInitBytes = Ukey2Message(type: .clientInit,
                                           data: clientInit.serialized()).serialized()
        try await channel.send(frame: clientInitBytes)

        // 3. Ukey2ServerInit.
        let serverInitBytes = try await channel.receiveFrame()
        let serverInitMessage = try Ukey2Message(serialized: serverInitBytes)
        guard serverInitMessage.messageType == .serverInit else {
            throw QuickShareError.handshakeFailed("expected server init")
        }
        let serverInit = try Ukey2ServerInit(serialized: serverInitMessage.messageData ?? Data())
        guard serverInit.version == 1 else {
            throw QuickShareError.handshakeFailed("unsupported UKEY2 version")
        }
        guard serverInit.random?.count == 32 else {
            throw QuickShareError.handshakeFailed("bad server random")
        }
        guard serverInit.handshakeCipher == .p256Sha512 else {
            throw QuickShareError.handshakeFailed("unsupported handshake cipher")
        }
        guard let serverKeyBytes = serverInit.publicKey else {
            throw QuickShareError.missingField("serverInit.publicKey")
        }
        let serverGeneric = try GenericPublicKey(serialized: serverKeyBytes)
        guard let serverEc = serverGeneric.ecP256PublicKey else {
            throw QuickShareError.missingField("server public key")
        }
        let peerKey = try UKey2.publicKey(from: serverEc)

        // 4. Ukey2ClientFinished — the same bytes the commitment covered.
        try await channel.send(frame: clientFinishedBytes)

        let keys = try UKey2.deriveSessionKeys(
            ourPrivateKey: keyPair.privateKey,
            peerPublicKey: peerKey,
            clientInitBytes: clientInitBytes,
            serverInitBytes: serverInitBytes,
            isServer: false)

        // 5. ConnectionResponse in the clear, then encryption is live.
        var accept = ConnectionResponseFrame()
        accept.response = .accept
        accept.status = 0
        accept.osInfo = OsInfo(type: .apple)
        var responseFrame = V1Frame()
        responseFrame.type = .connectionResponse
        responseFrame.connectionResponse = accept
        try await channel.send(frame: OfflineFrame.wrapping(responseFrame).serialized())

        let peerResponse = try OfflineFrame(serialized: try await channel.receiveFrame())
        guard peerResponse.v1?.connectionResponse?.response == .accept else {
            throw QuickShareError.rejected(.userRejected)
        }

        secure = SecureChannel(channel: channel, keys: keys)
        return keys
    }

    private func exchangeSetupFrames() async throws {
        guard let secure else { throw QuickShareError.internalFailure("no secure channel") }
        try await secure.sendSetupFrame(.pairedKeyEncryption(
            secretIDHash: Data.secureRandom(count: 6),
            signedData: Data.secureRandom(count: 72)))

        var sawEncryption = false
        var sawResult = false
        while !(sawEncryption && sawResult) {
            switch try await secure.receive() {
            case .setupFrame(let frame):
                switch frame.v1?.type {
                case .pairedKeyEncryption:
                    sawEncryption = true
                    try await secure.sendSetupFrame(.pairedKeyResult(.unable))
                case .pairedKeyResult:
                    sawResult = true
                case .cancel:
                    throw QuickShareError.rejected(.userCanceled)
                default:
                    continue
                }
            case .keepAlive:
                try await secure.sendKeepAlive(ack: true)
            case .disconnected:
                throw QuickShareError.connectionLost
            default:
                continue
            }
        }
    }

    private func sendIntroductionAndAwaitConsent() async throws {
        guard let secure else { throw QuickShareError.internalFailure("no secure channel") }

        var introduction = IntroductionFrame()
        for file in files {
            var meta = SharingFileMetadata()
            meta.name = file.name
            meta.size = file.size
            meta.mimeType = file.mimeType
            meta.type = Self.fileType(for: file)
            let payloadID = Int64.random(in: Int64.min...Int64.max)
            meta.payloadID = payloadID
            payloadIDs.append(payloadID)
            introduction.fileMetadata.append(meta)
            totalBytes += file.size
        }
        try await secure.sendSetupFrame(.introduction(introduction))

        // Wait for the remote user's decision.
        while true {
            switch try await secure.receive() {
            case .setupFrame(let frame):
                guard let v1 = frame.v1 else { continue }
                if v1.type == .cancel { throw QuickShareError.rejected(.userCanceled) }
                guard v1.type == .response, let status = v1.connectionResponse?.status else { continue }
                switch status {
                case .accept:
                    continuation?.yield(.accepted)
                    return
                case .reject, .unknown:      throw QuickShareError.rejected(.userRejected)
                case .notEnoughSpace:        throw QuickShareError.rejected(.notEnoughSpace)
                case .unsupportedAttachmentType: throw QuickShareError.rejected(.unsupportedType)
                case .timedOut:              throw QuickShareError.rejected(.timedOut)
                }
            case .keepAlive:
                try await secure.sendKeepAlive(ack: true)
            case .disconnected:
                throw QuickShareError.connectionLost
            default:
                continue
            }
        }
    }

    private func sendFiles() async throws {
        guard let secure else { throw QuickShareError.internalFailure("no secure channel") }

        for (index, file) in files.enumerated() {
            guard !cancelled else { throw QuickShareError.rejected(.userCanceled) }
            let payloadID = payloadIDs[index]
            guard let handle = try? FileHandle(forReadingFrom: file.url) else {
                throw QuickShareError.localFailure("couldn't read \(file.name)")
            }
            defer { try? handle.close() }

            var offset: Int64 = 0
            while offset < file.size {
                guard !cancelled else { throw QuickShareError.rejected(.userCanceled) }
                // Distinguish a read failure from end-of-file: silently sending
                // short would leave the receiver waiting on bytes that never come.
                let chunkData: Data?
                do {
                    chunkData = try handle.read(upToCount: Self.chunkSize)
                } catch {
                    throw QuickShareError.localFailure("couldn't read \(file.name)")
                }
                guard let body = chunkData, !body.isEmpty else { break }

                var header = PayloadHeader()
                header.id = payloadID
                header.type = .file
                header.totalSize = file.size
                header.isSensitive = false

                var chunk = PayloadChunk()
                chunk.offset = offset
                chunk.flags = 0
                chunk.body = body

                var transfer = PayloadTransferFrame()
                transfer.packetType = .data
                transfer.payloadHeader = header
                transfer.payloadChunk = chunk
                try await secure.send(.payloadTransfer(transfer))

                offset += Int64(body.count)
                sentBytes += Int64(body.count)
                if totalBytes > 0 {
                    continuation?.yield(.progress(min(1.0, Double(sentBytes) / Double(totalBytes))))
                }
            }

            // The size went out in the introduction the peer consented to, so a
            // file that shrank underneath us is an error, not a short send.
            guard offset == file.size else {
                throw QuickShareError.localFailure("\(file.name) changed while sending")
            }

            // Empty final chunk marks end of file.
            var header = PayloadHeader()
            header.id = payloadID
            header.type = .file
            header.totalSize = file.size
            header.isSensitive = false

            var endChunk = PayloadChunk()
            endChunk.offset = offset
            endChunk.flags = PayloadChunk.lastChunkFlag

            var transfer = PayloadTransferFrame()
            transfer.packetType = .data
            transfer.payloadHeader = header
            transfer.payloadChunk = endChunk
            try await secure.send(.payloadTransfer(transfer))
        }

        try? await secure.sendDisconnect()
        await finish(.finished)
    }

    /// Best-effort content classification from the MIME type.
    private static func fileType(for file: OutgoingFile) -> SharingFileType {
        if file.mimeType.hasPrefix("image/") { return .image }
        if file.mimeType.hasPrefix("video/") { return .video }
        if file.mimeType.hasPrefix("audio/") { return .audio }
        if file.url.pathExtension.lowercased() == "apk" { return .androidApp }
        return .unknown
    }

    private func finish(_ event: OutboundEvent) async {
        guard !finished else { return }
        finished = true
        continuation?.yield(event)
        continuation?.finish()
        continuation = nil
        await channel.close()
    }
}

public extension OutgoingFile {
    /// Builds an outgoing file from a URL, resolving size and MIME type.
    static func from(url: URL) throws -> OutgoingFile {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let size = Int64(values.fileSize ?? 0)
        let mime = values.contentType?.preferredMIMEType ?? "application/octet-stream"
        // The name goes to a remote device; keep it to one plain component.
        return OutgoingFile(url: url,
                            name: ReceivedFileName.sanitize(url.lastPathComponent),
                            size: size,
                            mimeType: mime)
    }
}
