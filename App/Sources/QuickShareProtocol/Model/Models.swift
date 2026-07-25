import Foundation

/// A device on the local network.
public struct QuickShareDevice: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let type: DeviceType

    public init(id: String, name: String, type: DeviceType) {
        self.id = id
        self.name = name
        self.type = type
    }

    public enum DeviceType: Int32, Sendable {
        case unknown = 0
        case phone = 1
        case tablet = 2
        case computer = 3

        public init(rawDeviceType: Int) {
            self = DeviceType(rawValue: Int32(rawDeviceType)) ?? .unknown
        }
    }
}

/// One file inside an incoming offer.
public struct IncomingFile: Sendable, Equatable {
    public let name: String
    public let size: Int64
    public let mimeType: String
    public let payloadID: Int64

    public init(name: String, size: Int64, mimeType: String, payloadID: Int64) {
        self.name = name
        self.size = size
        self.mimeType = mimeType
        self.payloadID = payloadID
    }
}

/// What a peer is offering us, presented for the user to accept or decline.
public struct IncomingOffer: Sendable, Equatable {
    public let id: String
    public let device: QuickShareDevice
    public let files: [IncomingFile]
    /// Present instead of files when the peer is sharing a link.
    public let textTitle: String?
    /// The verification code, for the user to compare against the other screen.
    public let pinCode: String

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    public init(id: String, device: QuickShareDevice, files: [IncomingFile],
                textTitle: String?, pinCode: String) {
        self.id = id
        self.device = device
        self.files = files
        self.textTitle = textTitle
        self.pinCode = pinCode
    }
}

/// Events a receiving session reports.
public enum InboundEvent: Sendable {
    /// The peer has offered files; answer with `respond(accept:)`.
    case offerReceived(IncomingOffer)
    case progress(Double)
    /// Finished successfully, with where the files landed.
    case finished(savedFiles: [URL])
    case failed(QuickShareError)
}

/// Events a sending session reports.
public enum OutboundEvent: Sendable {
    /// Handshake done; `pinCode` should be shown so the user can compare it.
    case connected(pinCode: String)
    /// The remote user accepted; bytes are flowing.
    case accepted
    case progress(Double)
    case finished
    case failed(QuickShareError)
}

/// A file queued to send.
public struct OutgoingFile: Sendable {
    public let url: URL
    public let name: String
    public let size: Int64
    public let mimeType: String

    public init(url: URL, name: String, size: Int64, mimeType: String) {
        self.url = url
        self.name = name
        self.size = size
        self.mimeType = mimeType
    }
}
