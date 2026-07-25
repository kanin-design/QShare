import Foundation

// wire_format.proto — the Quick Share application layer that rides inside
// Nearby Connections' bytes payloads: what's being offered, and the accept or
// decline that answers it.

public enum SharingFrameVersion: Int, Sendable {
    case unknownVersion = 0
    case v1 = 1
}

public enum SharingFrameType: Int, Sendable {
    case unknownFrameType = 0
    case introduction = 1
    case response = 2
    case pairedKeyEncryption = 3
    case pairedKeyResult = 4
    case certificateInfo = 5
    case cancel = 6
    case progressUpdate = 7
}

public enum SharingFileType: Int, Sendable {
    case unknown = 0
    case image = 1
    case video = 2
    case androidApp = 3
    case audio = 4
    case document = 5
    case contactCard = 6
}

public enum SharingTextType: Int, Sendable {
    case unknown = 0
    case text = 1
    case url = 2
    case address = 3
    case phoneNumber = 4
}

public enum SharingResponseStatus: Int, Sendable {
    case unknown = 0
    case accept = 1
    case reject = 2
    case notEnoughSpace = 3
    case unsupportedAttachmentType = 4
    case timedOut = 5
}

public enum PairedKeyResultStatus: Int, Sendable {
    case unknown = 0
    case success = 1
    case fail = 2
    case unable = 3
}

public struct SharingFileMetadata: ProtoMessage {
    public var name: String?
    public var type: SharingFileType?
    public var payloadID: Int64?
    public var size: Int64?
    public var mimeType: String?
    public var id: Int64?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = name { w.write(field: 1, string: v) }
        if let v = type { w.write(field: 2, enumValue: v.rawValue) }
        if let v = payloadID { w.write(field: 3, int64: v) }
        if let v = size { w.write(field: 4, int64: v) }
        if let v = mimeType { w.write(field: 5, string: v) }
        if let v = id { w.write(field: 6, int64: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .lengthDelimited): name = try reader.readString()
        case (2, .varint): type = SharingFileType(rawValue: Int(try reader.readInt32()))
        case (3, .varint): payloadID = try reader.readInt64()
        case (4, .varint): size = try reader.readInt64()
        case (5, .lengthDelimited): mimeType = try reader.readString()
        case (6, .varint): id = try reader.readInt64()
        default: return false
        }
        return true
    }
}

public struct SharingTextMetadata: ProtoMessage {
    public var textTitle: String?
    public var type: SharingTextType?
    public var payloadID: Int64?
    public var size: Int64?
    public var id: Int64?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = textTitle { w.write(field: 2, string: v) }
        if let v = type { w.write(field: 3, enumValue: v.rawValue) }
        if let v = payloadID { w.write(field: 4, int64: v) }
        if let v = size { w.write(field: 5, int64: v) }
        if let v = id { w.write(field: 6, int64: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (2, .lengthDelimited): textTitle = try reader.readString()
        case (3, .varint): type = SharingTextType(rawValue: Int(try reader.readInt32()))
        case (4, .varint): payloadID = try reader.readInt64()
        case (5, .varint): size = try reader.readInt64()
        case (6, .varint): id = try reader.readInt64()
        default: return false
        }
        return true
    }
}

public struct IntroductionFrame: ProtoMessage {
    public var fileMetadata: [SharingFileMetadata] = []
    public var textMetadata: [SharingTextMetadata] = []

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        w.write(field: 1, repeated: fileMetadata)
        w.write(field: 2, repeated: textMetadata)
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .lengthDelimited): try decodeNestedAppending(&fileMetadata, from: &reader)
        case (2, .lengthDelimited): try decodeNestedAppending(&textMetadata, from: &reader)
        default: return false
        }
        return true
    }
}

public struct SharingConnectionResponseFrame: ProtoMessage {
    public var status: SharingResponseStatus?

    public init() {}
    public init(status: SharingResponseStatus) { self.status = status }

    public func encode(to w: inout ProtoWriter) {
        if let v = status { w.write(field: 1, enumValue: v.rawValue) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): status = SharingResponseStatus(rawValue: Int(try reader.readInt32()))
        default: return false
        }
        return true
    }
}

public struct PairedKeyEncryptionFrame: ProtoMessage {
    public var signedData: Data?
    public var secretIDHash: Data?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = signedData { w.write(field: 1, bytes: v) }
        if let v = secretIDHash { w.write(field: 2, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .lengthDelimited): signedData = try reader.readBytes()
        case (2, .lengthDelimited): secretIDHash = try reader.readBytes()
        default: return false
        }
        return true
    }
}

public struct PairedKeyResultFrame: ProtoMessage {
    public var status: PairedKeyResultStatus?

    public init() {}
    public init(status: PairedKeyResultStatus) { self.status = status }

    public func encode(to w: inout ProtoWriter) {
        if let v = status { w.write(field: 1, enumValue: v.rawValue) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): status = PairedKeyResultStatus(rawValue: Int(try reader.readInt32()))
        default: return false
        }
        return true
    }
}

public struct SharingV1Frame: ProtoMessage {
    public var type: SharingFrameType?
    public var introduction: IntroductionFrame?
    public var connectionResponse: SharingConnectionResponseFrame?
    public var pairedKeyEncryption: PairedKeyEncryptionFrame?
    public var pairedKeyResult: PairedKeyResultFrame?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = type { w.write(field: 1, enumValue: v.rawValue) }
        if let v = introduction { w.write(field: 2, message: v) }
        if let v = connectionResponse { w.write(field: 3, message: v) }
        if let v = pairedKeyEncryption { w.write(field: 4, message: v) }
        if let v = pairedKeyResult { w.write(field: 5, message: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): type = SharingFrameType(rawValue: Int(try reader.readInt32()))
        case (2, .lengthDelimited): try decodeNested(&introduction, from: &reader)
        case (3, .lengthDelimited): try decodeNested(&connectionResponse, from: &reader)
        case (4, .lengthDelimited): try decodeNested(&pairedKeyEncryption, from: &reader)
        case (5, .lengthDelimited): try decodeNested(&pairedKeyResult, from: &reader)
        default: return false
        }
        return true
    }
}

public struct SharingFrame: ProtoMessage {
    public var version: SharingFrameVersion?
    public var v1: SharingV1Frame?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = version { w.write(field: 1, enumValue: v.rawValue) }
        if let v = v1 { w.write(field: 2, message: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): version = SharingFrameVersion(rawValue: Int(try reader.readInt32()))
        case (2, .lengthDelimited): try decodeNested(&v1, from: &reader)
        default: return false
        }
        return true
    }

    // MARK: Convenience constructors

    public static func wrapping(_ body: SharingV1Frame) -> SharingFrame {
        var f = SharingFrame()
        f.version = .v1
        f.v1 = body
        return f
    }

    public static func pairedKeyEncryption(secretIDHash: Data, signedData: Data) -> SharingFrame {
        var inner = PairedKeyEncryptionFrame()
        inner.signedData = signedData
        inner.secretIDHash = secretIDHash
        var v1 = SharingV1Frame()
        v1.type = .pairedKeyEncryption
        v1.pairedKeyEncryption = inner
        return .wrapping(v1)
    }

    public static func pairedKeyResult(_ status: PairedKeyResultStatus) -> SharingFrame {
        var v1 = SharingV1Frame()
        v1.type = .pairedKeyResult
        v1.pairedKeyResult = PairedKeyResultFrame(status: status)
        return .wrapping(v1)
    }

    public static func response(_ status: SharingResponseStatus) -> SharingFrame {
        var v1 = SharingV1Frame()
        v1.type = .response
        v1.connectionResponse = SharingConnectionResponseFrame(status: status)
        return .wrapping(v1)
    }

    public static func cancel() -> SharingFrame {
        var v1 = SharingV1Frame()
        v1.type = .cancel
        return .wrapping(v1)
    }

    public static func introduction(_ intro: IntroductionFrame) -> SharingFrame {
        var v1 = SharingV1Frame()
        v1.type = .introduction
        v1.introduction = intro
        return .wrapping(v1)
    }
}
