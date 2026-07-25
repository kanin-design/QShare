import Foundation

// securemessage.proto — the signed/encrypted envelope every post-handshake
// frame travels in. Field numbers mirror Google's securemessage.proto.

public enum SigScheme: Int, Sendable {
    case hmacSha256 = 1
    case ecdsaP256Sha256 = 2
    case rsa2048Sha256 = 3
}

public enum EncScheme: Int, Sendable {
    case none = 1
    case aes256Cbc = 2
}

public enum PublicKeyType: Int, Sendable {
    case ecP256 = 1
    case rsa2048 = 2
    case dh2048Modp = 3
}

/// The outermost envelope: an opaque `headerAndBody` plus its signature.
public struct SecureMessage: ProtoMessage {
    public var headerAndBody: Data?
    public var signature: Data?

    public init() {}
    public init(headerAndBody: Data, signature: Data) {
        self.headerAndBody = headerAndBody
        self.signature = signature
    }

    public func encode(to w: inout ProtoWriter) {
        if let v = headerAndBody { w.write(field: 1, bytes: v) }
        if let v = signature { w.write(field: 2, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .lengthDelimited): headerAndBody = try reader.readBytes()
        case (2, .lengthDelimited): signature = try reader.readBytes()
        default: return false
        }
        return true
    }

    public func validate() throws {
        guard headerAndBody != nil else { throw ProtoWireError.missingRequiredField("SecureMessage.headerAndBody") }
        guard signature != nil else { throw ProtoWireError.missingRequiredField("SecureMessage.signature") }
    }
}

public struct SecureMessageHeader: ProtoMessage {
    public var signatureScheme: SigScheme?
    public var encryptionScheme: EncScheme?
    public var verificationKeyID: Data?
    public var decryptionKeyID: Data?
    public var iv: Data?
    public var publicMetadata: Data?
    public var associatedDataLength: UInt32?

    public init() {}

    public func encode(to w: inout ProtoWriter) {
        if let v = signatureScheme { w.write(field: 1, enumValue: v.rawValue) }
        if let v = encryptionScheme { w.write(field: 2, enumValue: v.rawValue) }
        if let v = verificationKeyID { w.write(field: 3, bytes: v) }
        if let v = decryptionKeyID { w.write(field: 4, bytes: v) }
        if let v = iv { w.write(field: 5, bytes: v) }
        if let v = publicMetadata { w.write(field: 6, bytes: v) }
        if let v = associatedDataLength { w.write(field: 7, uint32: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint):
            let raw = Int(try reader.readInt32())
            guard let v = SigScheme(rawValue: raw) else {
                throw ProtoWireError.invalidEnumValue(field: "Header.signatureScheme", value: raw)
            }
            signatureScheme = v
        case (2, .varint):
            let raw = Int(try reader.readInt32())
            guard let v = EncScheme(rawValue: raw) else {
                throw ProtoWireError.invalidEnumValue(field: "Header.encryptionScheme", value: raw)
            }
            encryptionScheme = v
        case (3, .lengthDelimited): verificationKeyID = try reader.readBytes()
        case (4, .lengthDelimited): decryptionKeyID = try reader.readBytes()
        case (5, .lengthDelimited): iv = try reader.readBytes()
        case (6, .lengthDelimited): publicMetadata = try reader.readBytes()
        case (7, .varint): associatedDataLength = try reader.readUInt32()
        default: return false
        }
        return true
    }

    public func validate() throws {
        guard signatureScheme != nil else { throw ProtoWireError.missingRequiredField("Header.signatureScheme") }
        guard encryptionScheme != nil else { throw ProtoWireError.missingRequiredField("Header.encryptionScheme") }
    }
}

public struct HeaderAndBody: ProtoMessage {
    public var header: SecureMessageHeader?
    public var body: Data?

    public init() {}
    public init(header: SecureMessageHeader, body: Data) {
        self.header = header
        self.body = body
    }

    public func encode(to w: inout ProtoWriter) {
        if let v = header { w.write(field: 1, message: v) }
        if let v = body { w.write(field: 2, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .lengthDelimited): try decodeNested(&header, from: &reader)
        case (2, .lengthDelimited): body = try reader.readBytes()
        default: return false
        }
        return true
    }

    public func validate() throws {
        guard header != nil else { throw ProtoWireError.missingRequiredField("HeaderAndBody.header") }
        guard body != nil else { throw ProtoWireError.missingRequiredField("HeaderAndBody.body") }
    }
}

public struct EcP256PublicKey: ProtoMessage {
    public var x: Data?
    public var y: Data?

    public init() {}
    public init(x: Data, y: Data) { self.x = x; self.y = y }

    public func encode(to w: inout ProtoWriter) {
        if let v = x { w.write(field: 1, bytes: v) }
        if let v = y { w.write(field: 2, bytes: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .lengthDelimited): x = try reader.readBytes()
        case (2, .lengthDelimited): y = try reader.readBytes()
        default: return false
        }
        return true
    }

    public func validate() throws {
        guard x != nil else { throw ProtoWireError.missingRequiredField("EcP256PublicKey.x") }
        guard y != nil else { throw ProtoWireError.missingRequiredField("EcP256PublicKey.y") }
    }
}

public struct GenericPublicKey: ProtoMessage {
    public var type: PublicKeyType?
    public var ecP256PublicKey: EcP256PublicKey?
    // Fields 3 (rsa2048) and 4 (dh2048) exist in the schema but are unused by
    // Quick Share; they are skipped on decode rather than modelled.

    public init() {}
    public init(ecP256: EcP256PublicKey) {
        self.type = .ecP256
        self.ecP256PublicKey = ecP256
    }

    public func encode(to w: inout ProtoWriter) {
        if let v = type { w.write(field: 1, enumValue: v.rawValue) }
        if let v = ecP256PublicKey { w.write(field: 2, message: v) }
    }

    public mutating func decode(field: UInt32, wireType: ProtoWireType,
                                reader: inout ProtoReader) throws -> Bool {
        switch (field, wireType) {
        case (1, .varint):
            let raw = Int(try reader.readInt32())
            guard let v = PublicKeyType(rawValue: raw) else {
                throw ProtoWireError.invalidEnumValue(field: "GenericPublicKey.type", value: raw)
            }
            type = v
        case (2, .lengthDelimited): try decodeNested(&ecP256PublicKey, from: &reader)
        default: return false
        }
        return true
    }

    public func validate() throws {
        guard type != nil else { throw ProtoWireError.missingRequiredField("GenericPublicKey.type") }
    }
}
