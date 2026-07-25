import Foundation

// offline_wire_formats.proto — Nearby Connections' transport framing: the
// connection handshake, keep-alives, and the payload transfer that carries
// everything else.
//
// Only the fields Quick Share actually exchanges are modelled. Unmodelled
// fields (bandwidth upgrade, auto-reconnect, location hints, …) are skipped on
// decode, which is both smaller and safer than carrying them around.

public enum OfflineFrameVersion: Int, Sendable {
    case unknownVersion = 0
    case v1 = 1
}

public enum V1FrameType: Int, Sendable {
    case unknownFrameType = 0
    case connectionRequest = 1
    case connectionResponse = 2
    case payloadTransfer = 3
    case keepAlive = 5
    case disconnection = 6
}

public enum PacketType: Int, Sendable {
    case unknownPacketType = 0
    case data = 1
    case control = 2
}

public enum PayloadType: Int, Sendable {
    case unknownPayloadType = 0
    case bytes = 1
    case file = 2
    case stream = 3
}

public enum OsType: Int, Sendable {
    case unknownOsType = 0
    case android = 1
    case chromeOs = 2
    case windows = 3
    case apple = 4
    case linux = 100
}

public enum ConnectionResponseStatus: Int, Sendable {
    case unknownResponseStatus = 0
    case accept = 1
    case reject = 2
}

public struct OsInfo: ProtoMessage {
    public var type: OsType?

    public init() {}
    public init(type: OsType) { self.type = type }

    public func encode(to w: inout ProtoWriter) {
        if let v = type { w.write(field: 1, enumValue: v.rawValue) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): type = OsType(rawValue: Int(try reader.readInt32()))
        default: return false
        }
        return true
    }
}

public struct ConnectionRequestFrame: ProtoMessage {
    public var endpointID: String?
    public var endpointName: String?
    public var endpointInfo: Data?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = endpointID { w.write(field: 1, string: v) }
        if let v = endpointName { w.write(field: 2, string: v) }
        if let v = endpointInfo { w.write(field: 6, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .lengthDelimited): endpointID = try reader.readString()
        case (2, .lengthDelimited): endpointName = try reader.readString()
        case (6, .lengthDelimited): endpointInfo = try reader.readBytes()
        default: return false
        }
        return true
    }
}

public struct ConnectionResponseFrame: ProtoMessage {
    public var status: Int32?
    public var response: ConnectionResponseStatus?
    public var osInfo: OsInfo?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = status { w.write(field: 1, int32: v) }
        if let v = response { w.write(field: 3, enumValue: v.rawValue) }
        if let v = osInfo { w.write(field: 4, message: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): status = try reader.readInt32()
        case (3, .varint): response = ConnectionResponseStatus(rawValue: Int(try reader.readInt32()))
        case (4, .lengthDelimited): try decodeNested(&osInfo, from: &reader)
        default: return false
        }
        return true
    }
}

public struct DisconnectionFrame: ProtoMessage {
    public var requestSafeToDisconnect: Bool?
    public var ackSafeToDisconnect: Bool?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = requestSafeToDisconnect { w.write(field: 1, bool: v) }
        if let v = ackSafeToDisconnect { w.write(field: 2, bool: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): requestSafeToDisconnect = try reader.readBool()
        case (2, .varint): ackSafeToDisconnect = try reader.readBool()
        default: return false
        }
        return true
    }
}

public struct KeepAliveFrame: ProtoMessage {
    public var ack: Bool?
    public var seqNum: UInt32?

    public init() {}
    public init(ack: Bool) { self.ack = ack }

    public func encode(to w: inout ProtoWriter) {
        if let v = ack { w.write(field: 1, bool: v) }
        if let v = seqNum { w.write(field: 2, uint32: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): ack = try reader.readBool()
        case (2, .varint): seqNum = try reader.readUInt32()
        default: return false
        }
        return true
    }
}

public struct PayloadHeader: ProtoMessage {
    public var id: Int64?
    public var type: PayloadType?
    public var totalSize: Int64?
    public var isSensitive: Bool?
    public var fileName: String?
    public var parentFolder: String?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = id { w.write(field: 1, int64: v) }
        if let v = type { w.write(field: 2, enumValue: v.rawValue) }
        if let v = totalSize { w.write(field: 3, int64: v) }
        if let v = isSensitive { w.write(field: 4, bool: v) }
        if let v = fileName { w.write(field: 5, string: v) }
        if let v = parentFolder { w.write(field: 6, string: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): id = try reader.readInt64()
        case (2, .varint): type = PayloadType(rawValue: Int(try reader.readInt32()))
        case (3, .varint): totalSize = try reader.readInt64()
        case (4, .varint): isSensitive = try reader.readBool()
        case (5, .lengthDelimited): fileName = try reader.readString()
        case (6, .lengthDelimited): parentFolder = try reader.readString()
        default: return false
        }
        return true
    }
}

public struct PayloadChunk: ProtoMessage {
    /// Bit 0 set means "last chunk".
    public static let lastChunkFlag: Int32 = 1

    public var flags: Int32?
    public var offset: Int64?
    public var body: Data?

    public init() {}

    public var isLastChunk: Bool { ((flags ?? 0) & Self.lastChunkFlag) == Self.lastChunkFlag }

    public func encode(to w: inout ProtoWriter) {
        if let v = flags { w.write(field: 1, int32: v) }
        if let v = offset { w.write(field: 2, int64: v) }
        if let v = body { w.write(field: 3, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): flags = try reader.readInt32()
        case (2, .varint): offset = try reader.readInt64()
        case (3, .lengthDelimited): body = try reader.readBytes()
        default: return false
        }
        return true
    }
}

public struct PayloadTransferFrame: ProtoMessage {
    public var packetType: PacketType?
    public var payloadHeader: PayloadHeader?
    public var payloadChunk: PayloadChunk?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = packetType { w.write(field: 1, enumValue: v.rawValue) }
        if let v = payloadHeader { w.write(field: 2, message: v) }
        if let v = payloadChunk { w.write(field: 3, message: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): packetType = PacketType(rawValue: Int(try reader.readInt32()))
        case (2, .lengthDelimited): try decodeNested(&payloadHeader, from: &reader)
        case (3, .lengthDelimited): try decodeNested(&payloadChunk, from: &reader)
        default: return false
        }
        return true
    }
}

public struct V1Frame: ProtoMessage {
    public var type: V1FrameType?
    public var connectionRequest: ConnectionRequestFrame?
    public var connectionResponse: ConnectionResponseFrame?
    public var payloadTransfer: PayloadTransferFrame?
    public var keepAlive: KeepAliveFrame?
    public var disconnection: DisconnectionFrame?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = type { w.write(field: 1, enumValue: v.rawValue) }
        if let v = connectionRequest { w.write(field: 2, message: v) }
        if let v = connectionResponse { w.write(field: 3, message: v) }
        if let v = payloadTransfer { w.write(field: 4, message: v) }
        if let v = keepAlive { w.write(field: 6, message: v) }
        if let v = disconnection { w.write(field: 7, message: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): type = V1FrameType(rawValue: Int(try reader.readInt32()))
        case (2, .lengthDelimited): try decodeNested(&connectionRequest, from: &reader)
        case (3, .lengthDelimited): try decodeNested(&connectionResponse, from: &reader)
        case (4, .lengthDelimited): try decodeNested(&payloadTransfer, from: &reader)
        case (6, .lengthDelimited): try decodeNested(&keepAlive, from: &reader)
        case (7, .lengthDelimited): try decodeNested(&disconnection, from: &reader)
        default: return false
        }
        return true
    }
}

public struct OfflineFrame: ProtoMessage {
    public var version: OfflineFrameVersion?
    public var v1: V1Frame?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = version { w.write(field: 1, enumValue: v.rawValue) }
        if let v = v1 { w.write(field: 2, message: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): version = OfflineFrameVersion(rawValue: Int(try reader.readInt32()))
        case (2, .lengthDelimited): try decodeNested(&v1, from: &reader)
        default: return false
        }
        return true
    }

    // MARK: Convenience constructors

    public static func wrapping(_ body: V1Frame) -> OfflineFrame {
        var f = OfflineFrame()
        f.version = .v1
        f.v1 = body
        return f
    }

    public static func keepAlive(ack: Bool) -> OfflineFrame {
        var v1 = V1Frame()
        v1.type = .keepAlive
        v1.keepAlive = KeepAliveFrame(ack: ack)
        return .wrapping(v1)
    }

    public static func disconnection() -> OfflineFrame {
        var v1 = V1Frame()
        v1.type = .disconnection
        v1.disconnection = DisconnectionFrame()
        return .wrapping(v1)
    }

    public static func payloadTransfer(_ transfer: PayloadTransferFrame) -> OfflineFrame {
        var v1 = V1Frame()
        v1.type = .payloadTransfer
        v1.payloadTransfer = transfer
        return .wrapping(v1)
    }
}
