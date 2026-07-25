import Foundation

// ukey.proto — the UKEY2 authenticated key-exchange handshake messages.

public enum Ukey2HandshakeCipher: Int, Sendable {
    case reserved = 0
    case p256Sha512 = 100
    case curve25519Sha512 = 200
}

public enum Ukey2MessageType: Int, Sendable {
    case unknownDoNotUse = 0
    case alert = 1
    case clientInit = 2
    case serverInit = 3
    case clientFinish = 4
}

public enum Ukey2AlertType: Int, Sendable {
    case badMessage = 1
    case badMessageType = 2
    case incorrectMessage = 3
    case badMessageData = 4
    case badVersion = 100
    case badRandom = 101
    case badHandshakeCipher = 102
    case badNextProtocol = 103
    case badPublicKey = 104
    case internalError = 200
}

/// Envelope for every handshake message.
public struct Ukey2Message: ProtoMessage {
    public var messageType: Ukey2MessageType?
    public var messageData: Data?

    public init() {}
    public init(type: Ukey2MessageType, data: Data) {
        self.messageType = type
        self.messageData = data
    }

    public func encode(to w: inout ProtoWriter) {
        if let v = messageType { w.write(field: 1, enumValue: v.rawValue) }
        if let v = messageData { w.write(field: 2, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint):
            let raw = Int(try reader.readInt32())
            guard let v = Ukey2MessageType(rawValue: raw) else {
                throw ProtoWireError.invalidEnumValue(field: "Ukey2Message.messageType", value: raw)
            }
            messageType = v
        case (2, .lengthDelimited): messageData = try reader.readBytes()
        default: return false
        }
        return true
    }

    public func validate() throws {
        guard messageType != nil else { throw ProtoWireError.missingRequiredField("Ukey2Message.messageType") }
    }
}

public struct Ukey2CipherCommitment: ProtoMessage {
    public var handshakeCipher: Ukey2HandshakeCipher?
    public var commitment: Data?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = handshakeCipher { w.write(field: 1, enumValue: v.rawValue) }
        if let v = commitment { w.write(field: 2, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint):
            // An unrecognised cipher is not fatal: the peer may offer several and
            // we simply won't select it.
            handshakeCipher = Ukey2HandshakeCipher(rawValue: Int(try reader.readInt32()))
        case (2, .lengthDelimited): commitment = try reader.readBytes()
        default: return false
        }
        return true
    }
}

public struct Ukey2ClientInit: ProtoMessage {
    public var version: Int32?
    public var random: Data?
    public var cipherCommitments: [Ukey2CipherCommitment] = []
    public var nextProtocol: String?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = version { w.write(field: 1, int32: v) }
        if let v = random { w.write(field: 2, bytes: v) }
        w.write(field: 3, repeated: cipherCommitments)
        if let v = nextProtocol { w.write(field: 4, string: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): version = try reader.readInt32()
        case (2, .lengthDelimited): random = try reader.readBytes()
        case (3, .lengthDelimited): try decodeNestedAppending(&cipherCommitments, from: &reader)
        case (4, .lengthDelimited): nextProtocol = try reader.readString()
        default: return false
        }
        return true
    }
}

public struct Ukey2ServerInit: ProtoMessage {
    public var version: Int32?
    public var random: Data?
    public var handshakeCipher: Ukey2HandshakeCipher?
    public var publicKey: Data?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = version { w.write(field: 1, int32: v) }
        if let v = random { w.write(field: 2, bytes: v) }
        if let v = handshakeCipher { w.write(field: 3, enumValue: v.rawValue) }
        if let v = publicKey { w.write(field: 4, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): version = try reader.readInt32()
        case (2, .lengthDelimited): random = try reader.readBytes()
        case (3, .varint): handshakeCipher = Ukey2HandshakeCipher(rawValue: Int(try reader.readInt32()))
        case (4, .lengthDelimited): publicKey = try reader.readBytes()
        default: return false
        }
        return true
    }
}

public struct Ukey2ClientFinished: ProtoMessage {
    public var publicKey: Data?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = publicKey { w.write(field: 1, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .lengthDelimited): publicKey = try reader.readBytes()
        default: return false
        }
        return true
    }
}

public struct Ukey2Alert: ProtoMessage {
    public var type: Ukey2AlertType?
    public var errorMessage: String?

    public init() {}
    public init(type: Ukey2AlertType) { self.type = type }

    public func encode(to w: inout ProtoWriter) {
        if let v = type { w.write(field: 1, enumValue: v.rawValue) }
        if let v = errorMessage { w.write(field: 2, string: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint): type = Ukey2AlertType(rawValue: Int(try reader.readInt32()))
        case (2, .lengthDelimited): errorMessage = try reader.readString()
        default: return false
        }
        return true
    }
}
