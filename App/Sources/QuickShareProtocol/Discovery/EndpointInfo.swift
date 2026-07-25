import Foundation

/// The small binary blob a device advertises about itself — in the mDNS TXT
/// record when browsing, and in the connection request when connecting.
///
/// Layout:
///   byte 0      flags: bit 4 set means "no name"; bits 1-3 are the device type
///   bytes 1-16  16 random bytes (purpose unknown; treated as opaque)
///   byte 17     device-name length, when a name is present
///   bytes 18..  device name, UTF-8
///   remainder   optional TLV records (type 1 carries QR handshake data)
public struct EndpointInfo: Sendable, Equatable {
    public var name: String?
    public var deviceType: QuickShareDevice.DeviceType
    public var qrCodeData: Data?

    /// Longest name we will emit or accept; the length field is a single byte.
    static let maxNameBytes = 255
    private static let noNameFlag: UInt8 = 0x10
    private static let headerLength = 18

    public init(name: String?, deviceType: QuickShareDevice.DeviceType, qrCodeData: Data? = nil) {
        self.name = name
        self.deviceType = deviceType
        self.qrCodeData = qrCodeData
    }

    // MARK: Decoding

    public init(serialized data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.headerLength else {
            throw QuickShareError.protocolViolation("endpoint info too short")
        }

        let flags = bytes[0]
        // Device type is bits 1-3.
        self.deviceType = QuickShareDevice.DeviceType(rawDeviceType: Int((flags & 0x0E) >> 1))

        var offset = 17
        if flags & Self.noNameFlag == 0 {
            let nameLength = Int(bytes[17])
            offset = 18
            guard bytes.count >= offset + nameLength else {
                throw QuickShareError.protocolViolation("endpoint info name overruns the buffer")
            }
            guard let decoded = String(bytes: bytes[offset..<(offset + nameLength)], encoding: .utf8) else {
                throw QuickShareError.protocolViolation("endpoint info name is not valid UTF-8")
            }
            self.name = decoded
            offset += nameLength
        } else {
            self.name = nil
            offset = 17
        }

        // Optional TLV tail. Every iteration consumes at least the 2-byte header,
        // so a malformed record can shorten the scan but never stall it.
        var qr: Data?
        while bytes.count - offset > 2 {
            let type = bytes[offset]
            let length = Int(bytes[offset + 1])
            offset += 2
            guard bytes.count - offset >= length else { break }
            if type == 1 { qr = Data(bytes[offset..<(offset + length)]) }
            offset += length
        }
        self.qrCodeData = qr
    }

    // MARK: Encoding

    public func serialized() -> Data {
        var out = Data()
        var flags = UInt8(deviceType.rawValue & 0x07) << 1
        if name == nil { flags |= Self.noNameFlag }
        out.append(flags)
        out.append(Data.secureRandom(count: 16))

        if let name {
            var nameBytes = [UInt8](name.utf8)
            if nameBytes.count > Self.maxNameBytes {
                // Truncate on a character boundary so the name stays valid UTF-8.
                var truncated = name
                while truncated.utf8.count > Self.maxNameBytes { truncated = String(truncated.dropLast()) }
                nameBytes = [UInt8](truncated.utf8)
            }
            out.append(UInt8(nameBytes.count))
            out.append(contentsOf: nameBytes)
        }
        return out
    }
}
