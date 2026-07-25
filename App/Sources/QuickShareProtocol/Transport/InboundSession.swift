import Foundation
import Network
import CryptoKit

/// Receives a transfer: performs the UKEY2 handshake as the server, presents the
/// peer's offer for consent, then writes the files.
///
/// Events are delivered on an `AsyncStream`; the caller answers an offer by
/// calling `respond(accept:)`.
public actor InboundSession {

    public let id: String
    private let channel: FrameChannel
    private let receiveDirectory: URL

    private var secure: SecureChannel?
    private var device: QuickShareDevice?
    private var pinCode: String?

    private var pendingFiles: [Int64: PendingFile] = [:]
    private var savedURLs: [URL] = []
    private var totalExpectedBytes: Int64 = 0
    private var totalReceivedBytes: Int64 = 0

    private var consent: CheckedContinuation<Bool, Never>?
    private var continuation: AsyncStream<InboundEvent>.Continuation?
    private var finished = false

    private struct PendingFile {
        let metadata: IncomingFile
        let destination: URL
        var handle: FileHandle?
        var bytesWritten: Int64 = 0
    }

    public init(connection: NWConnection, id: String, receiveDirectory: URL) {
        self.id = id
        self.channel = FrameChannel(connection: connection)
        self.receiveDirectory = receiveDirectory
    }

    /// Runs the session. The stream finishes when the transfer ends.
    public func events() -> AsyncStream<InboundEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            Task { await self.run() }
        }
    }

    /// Answers a pending offer.
    public func respond(accept: Bool) {
        consent?.resume(returning: accept)
        consent = nil
    }

    public func cancel() async {
        await finish(.failed(.rejected(.userCanceled)))
    }

    // MARK: Main loop

    private func run() async {
        do {
            try await channel.start()
            try await performHandshake()
            try await exchangeSetupFrames()
            try await receiveLoop()
        } catch let error as QuickShareError {
            await finish(.failed(error))
        } catch {
            await finish(.failed(.localFailure(error.localizedDescription)))
        }
    }

    // MARK: Handshake

    private func performHandshake() async throws {
        // 1. ConnectionRequest — carries the peer's name and device type.
        let requestFrame = try OfflineFrame(serialized: try await channel.receiveFrame())
        guard let request = requestFrame.v1?.connectionRequest,
              let endpointInfo = request.endpointInfo else {
            throw QuickShareError.missingField("connectionRequest.endpointInfo")
        }
        let info = try EndpointInfo(serialized: endpointInfo)
        device = QuickShareDevice(id: UUID().uuidString,
                                  name: info.name ?? request.endpointName ?? "Unknown device",
                                  type: info.deviceType)

        // 2. Ukey2ClientInit — the exact bytes matter; they go into the transcript.
        let clientInitBytes = try await channel.receiveFrame()
        let clientInitMessage = try Ukey2Message(serialized: clientInitBytes)
        guard clientInitMessage.messageType == .clientInit else {
            try await sendAlert(.badMessageType)
            throw QuickShareError.handshakeFailed("expected client init")
        }
        let clientInit = try Ukey2ClientInit(serialized: clientInitMessage.messageData ?? Data())
        guard clientInit.nextProtocol == "AES_256_CBC-HMAC_SHA256" else {
            try await sendAlert(.badNextProtocol)
            throw QuickShareError.handshakeFailed("unsupported next protocol")
        }
        guard clientInit.cipherCommitments.contains(where: { $0.handshakeCipher == .p256Sha512 }) else {
            try await sendAlert(.badHandshakeCipher)
            throw QuickShareError.handshakeFailed("no supported cipher offered")
        }

        // 3. Ukey2ServerInit — our ephemeral key.
        let keyPair = UKey2.KeyPair()
        var serverInit = Ukey2ServerInit()
        serverInit.version = 1
        serverInit.random = Data.secureRandom(count: 32)
        serverInit.handshakeCipher = .p256Sha512
        serverInit.publicKey = keyPair.genericPublicKey.serialized()
        let serverInitBytes = Ukey2Message(type: .serverInit, data: serverInit.serialized()).serialized()
        try await channel.send(frame: serverInitBytes)

        // 4. Ukey2ClientFinished — the peer's key.
        let finishMessage = try Ukey2Message(serialized: try await channel.receiveFrame())
        guard finishMessage.messageType == .clientFinish else {
            try await sendAlert(.badMessageType)
            throw QuickShareError.handshakeFailed("expected client finish")
        }
        let clientFinished = try Ukey2ClientFinished(serialized: finishMessage.messageData ?? Data())
        guard let peerKeyBytes = clientFinished.publicKey else {
            throw QuickShareError.missingField("clientFinished.publicKey")
        }
        let peerGeneric = try GenericPublicKey(serialized: peerKeyBytes)
        guard let peerEc = peerGeneric.ecP256PublicKey else {
            throw QuickShareError.missingField("peer public key")
        }
        let peerKey = try UKey2.publicKey(from: peerEc)

        let keys = try UKey2.deriveSessionKeys(
            ourPrivateKey: keyPair.privateKey,
            peerPublicKey: peerKey,
            clientInitBytes: clientInitBytes,
            serverInitBytes: serverInitBytes,
            isServer: true)
        pinCode = keys.pinCode

        // 5. ConnectionResponse, in the clear, then everything is encrypted.
        let response = try OfflineFrame(serialized: try await channel.receiveFrame())
        guard response.v1?.type == .connectionResponse else {
            throw QuickShareError.protocolViolation("expected a connection response")
        }
        var accept = ConnectionResponseFrame()
        accept.response = .accept
        accept.status = 0
        accept.osInfo = OsInfo(type: .apple)
        var v1 = V1Frame()
        v1.type = .connectionResponse
        v1.connectionResponse = accept
        try await channel.send(frame: OfflineFrame.wrapping(v1).serialized())

        secure = SecureChannel(channel: channel, keys: keys)
    }

    private func sendAlert(_ type: Ukey2AlertType) async throws {
        let alert = Ukey2Message(type: .alert, data: Ukey2Alert(type: type).serialized())
        try? await channel.send(frame: alert.serialized())
    }

    // MARK: Setup frames

    private func exchangeSetupFrames() async throws {
        guard let secure else { throw QuickShareError.internalFailure("no secure channel") }
        // The paired-key exchange is vestigial for us: we have no contact
        // certificates, so we send placeholders and answer `.unable`, which is
        // what the reference did and what Android tolerates.
        try await secure.sendSetupFrame(.pairedKeyEncryption(
            secretIDHash: Data.secureRandom(count: 6),
            signedData: Data.secureRandom(count: 72)))

        // Drive the exchange until the peer's introduction arrives.
        while true {
            switch try await secure.receive() {
            case .setupFrame(let frame):
                guard let type = frame.v1?.type else { continue }
                switch type {
                case .pairedKeyEncryption:
                    try await secure.sendSetupFrame(.pairedKeyResult(.unable))
                case .pairedKeyResult:
                    continue
                case .introduction:
                    guard let introduction = frame.v1?.introduction else {
                        throw QuickShareError.missingField("introduction")
                    }
                    try await handleIntroduction(introduction)
                    return
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

    private func handleIntroduction(_ introduction: IntroductionFrame) async throws {
        guard let secure, let device, let pinCode else {
            throw QuickShareError.internalFailure("session not ready")
        }

        // Text-only offers (a shared link) are surfaced but not written to disk.
        if introduction.fileMetadata.isEmpty, let text = introduction.textMetadata.first {
            let offer = IncomingOffer(id: id, device: device, files: [],
                                      textTitle: text.textTitle ?? "Link", pinCode: pinCode)
            let accepted = await requestConsent(offer)
            try await secure.sendSetupFrame(.response(accepted ? .accept : .reject))
            if !accepted { throw QuickShareError.rejected(.userRejected) }
            return
        }

        guard !introduction.fileMetadata.isEmpty else {
            try await secure.sendSetupFrame(.response(.unsupportedAttachmentType))
            throw QuickShareError.rejected(.unsupportedType)
        }

        // Resolve destinations before asking, so a bad name is refused up front.
        var files: [IncomingFile] = []
        var pending: [Int64: PendingFile] = [:]
        for meta in introduction.fileMetadata {
            guard let payloadID = meta.payloadID else {
                throw QuickShareError.missingField("fileMetadata.payloadID")
            }
            let size = meta.size ?? 0
            guard size >= 0 else {
                throw QuickShareError.protocolViolation("negative file size")
            }
            let safeName = ReceivedFileName.sanitize(meta.name ?? "")
            let destination = try ReceivedFileName.uniqueDestination(
                for: safeName, in: receiveDirectory)
            let file = IncomingFile(name: destination.lastPathComponent, size: size,
                                    mimeType: meta.mimeType ?? "application/octet-stream",
                                    payloadID: payloadID)
            files.append(file)
            pending[payloadID] = PendingFile(metadata: file, destination: destination)
        }

        let offer = IncomingOffer(id: id, device: device, files: files,
                                  textTitle: nil, pinCode: pinCode)
        let accepted = await requestConsent(offer)
        guard accepted else {
            try await secure.sendSetupFrame(.response(.reject))
            throw QuickShareError.rejected(.userRejected)
        }

        pendingFiles = pending
        totalExpectedBytes = files.reduce(0) { $0 + $1.size }
        totalReceivedBytes = 0

        // Only create files once the user has actually said yes.
        for (payloadID, var file) in pendingFiles {
            FileManager.default.createFile(atPath: file.destination.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: file.destination) else {
                throw QuickShareError.localFailure("couldn't create \(file.destination.lastPathComponent)")
            }
            file.handle = handle
            pendingFiles[payloadID] = file
        }
        try await secure.sendSetupFrame(.response(.accept))
    }

    private func requestConsent(_ offer: IncomingOffer) async -> Bool {
        continuation?.yield(.offerReceived(offer))
        return await withCheckedContinuation { continuation in
            self.consent = continuation
        }
    }

    // MARK: Transfer

    private func receiveLoop() async throws {
        guard let secure else { throw QuickShareError.internalFailure("no secure channel") }
        while !finished {
            switch try await secure.receive() {
            case .fileChunk(let header, let chunk):
                try writeChunk(header: header, chunk: chunk)
                if pendingFiles.isEmpty {
                    try? await secure.sendDisconnect()
                    await finish(.finished(savedFiles: savedURLs))
                    return
                }
            case .setupFrame(let frame):
                if frame.v1?.type == .cancel {
                    throw QuickShareError.rejected(.userCanceled)
                }
            case .keepAlive:
                try await secure.sendKeepAlive(ack: true)
            case .disconnected:
                if pendingFiles.isEmpty {
                    await finish(.finished(savedFiles: savedURLs))
                } else {
                    throw QuickShareError.connectionLost
                }
                return
            case .bytesPayload, .ignored:
                continue
            }
        }
    }

    private func writeChunk(header: PayloadHeader, chunk: PayloadChunk) throws {
        guard let payloadID = header.id, var file = pendingFiles[payloadID] else {
            throw QuickShareError.protocolViolation("chunk for an unknown payload")
        }
        guard chunk.offset ?? 0 == file.bytesWritten else {
            throw QuickShareError.protocolViolation("unexpected file chunk offset")
        }

        if let body = chunk.body, !body.isEmpty {
            // Never write more than was declared and consented to.
            guard file.bytesWritten + Int64(body.count) <= file.metadata.size else {
                throw QuickShareError.protocolViolation("file exceeded its declared size")
            }
            file.handle?.write(body)
            file.bytesWritten += Int64(body.count)
            totalReceivedBytes += Int64(body.count)
            pendingFiles[payloadID] = file

            if totalExpectedBytes > 0 {
                continuation?.yield(.progress(
                    min(1.0, Double(totalReceivedBytes) / Double(totalExpectedBytes))))
            }
        }

        if chunk.isLastChunk {
            try? file.handle?.close()
            savedURLs.append(file.destination)
            pendingFiles.removeValue(forKey: payloadID)
        }
    }

    // MARK: Teardown

    private func finish(_ event: InboundEvent) async {
        guard !finished else { return }
        finished = true

        // A failed transfer must not leave half-written files behind.
        if case .finished = event {} else {
            for (_, file) in pendingFiles {
                try? file.handle?.close()
                try? FileManager.default.removeItem(at: file.destination)
            }
        }
        pendingFiles.removeAll()

        continuation?.yield(event)
        continuation?.finish()
        continuation = nil
        await channel.close()
    }
}
