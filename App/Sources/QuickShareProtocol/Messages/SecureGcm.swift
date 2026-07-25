import Foundation

// securegcm.proto — the inner message carried inside a SecureMessage body, plus
// the metadata tag that identifies it.

/// `Securegcm.Type`. Only the one value Quick Share uses is modelled; anything
/// else decodes as `.other` rather than failing, since this field is purely
/// descriptive.
public enum GcmType: Sendable, Equatable {
    case deviceToDeviceMessage
    case other(Int)

    public var rawValue: Int {
        switch self {
        case .deviceToDeviceMessage: return 13
        case .other(let v): return v
        }
    }

    public init(rawValue: Int) {
        self = rawValue == 13 ? .deviceToDeviceMessage : .other(rawValue)
    }
}

public struct GcmMetadata: ProtoMessage {
    public var type: GcmType?
    public var version: Int32?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = type { w.write(field: 1, enumValue: v.rawValue) }
        if let v = version { w.write(field: 2, int32: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): type = GcmType(rawValue: Int(try reader.readInt32()))
        case (2, .varint): version = try reader.readInt32()
        default: return false
        }
        return true
    }

    public func validate() throws {
        guard type != nil else { throw ProtoWireError.missingRequiredField("GcmMetadata.type") }
    }
}

/// The decrypted payload of every post-handshake frame.
///
/// Note the wire order: `message` is field 1 and `sequenceNumber` is field 2,
/// regardless of the order they're assigned in code.
public struct DeviceToDeviceMessage: ProtoMessage {
    public var message: Data?
    public var sequenceNumber: Int32?

    public init() {}
    public init(message: Data, sequenceNumber: Int32) {
        self.message = message
        self.sequenceNumber = sequenceNumber
    }

    public func encode(to w: inout ProtoWriter) {
        if let v = message { w.write(field: 1, bytes: v) }
        if let v = sequenceNumber { w.write(field: 2, int32: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .lengthDelimited): message = try reader.readBytes()
        case (2, .varint): sequenceNumber = try reader.readInt32()
        default: return false
        }
        return true
    }

    public func validate() throws {
        guard message != nil else { throw ProtoWireError.missingRequiredField("DeviceToDeviceMessage.message") }
        guard sequenceNumber != nil else { throw ProtoWireError.missingRequiredField("DeviceToDeviceMessage.sequenceNumber") }
    }
}
