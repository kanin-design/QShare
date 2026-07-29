import Foundation
import CryptoKit
import CommonCrypto

/// Seals and opens the AES-256-CBC + HMAC-SHA256 envelope every post-handshake
/// frame travels in.
///
/// Encrypt-then-MAC: the HMAC covers the serialized `HeaderAndBody`, and it is
/// verified *before* anything is decrypted. That ordering is what makes the
/// PKCS#7 padding check below safe to perform — an attacker cannot get us to
/// decrypt, or to reveal a padding result, without already holding the MAC key.
public struct SecureMessageCodec: Sendable {

    private let encryptKey: SymmetricKey
    private let decryptKey: SymmetricKey
    private let sendHmacKey: SymmetricKey
    private let recvHmacKey: SymmetricKey

    public init(keys: UKey2.SessionKeys) {
        self.encryptKey = keys.encryptKey
        self.decryptKey = keys.decryptKey
        self.sendHmacKey = keys.sendHmacKey
        self.recvHmacKey = keys.recvHmacKey
    }

    // MARK: Seal

    public func seal(_ plaintext: Data) throws -> SecureMessage {
        let iv = Data.secureRandom(count: kCCBlockSizeAES128)
        let ciphertext = try Self.crypt(operation: CCOperation(kCCEncrypt),
                                        key: encryptKey, iv: iv, input: plaintext)

        var metadata = GcmMetadata()
        metadata.type = .deviceToDeviceMessage
        metadata.version = 1

        var header = SecureMessageHeader()
        header.signatureScheme = .hmacSha256
        header.encryptionScheme = .aes256Cbc
        header.iv = iv
        header.publicMetadata = metadata.serialized()

        let headerAndBody = HeaderAndBody(header: header, body: ciphertext).serialized()
        let signature = Data(HMAC<SHA256>.authenticationCode(for: headerAndBody, using: sendHmacKey))
        return SecureMessage(headerAndBody: headerAndBody, signature: signature)
    }

    // MARK: Open

    public func open(_ message: SecureMessage) throws -> Data {
        guard let headerAndBody = message.headerAndBody, let signature = message.signature else {
            throw QuickShareError.protocolViolation("secure message is missing a field")
        }

        // Verify first, in constant time, and bail before touching the ciphertext.
        let expected = Data(HMAC<SHA256>.authenticationCode(for: headerAndBody, using: recvHmacKey))
        guard constantTimeEquals(expected, signature) else {
            throw QuickShareError.authenticationFailed
        }

        let parsed = try HeaderAndBody(serialized: headerAndBody)
        guard let header = parsed.header, let body = parsed.body else {
            throw QuickShareError.protocolViolation("secure message body is missing a field")
        }
        guard header.encryptionScheme == .aes256Cbc else {
            throw QuickShareError.protocolViolation("unsupported encryption scheme")
        }
        guard header.signatureScheme == .hmacSha256 else {
            throw QuickShareError.protocolViolation("unsupported signature scheme")
        }
        guard let iv = header.iv, iv.count == kCCBlockSizeAES128 else {
            throw QuickShareError.protocolViolation("missing or malformed IV")
        }
        return try Self.crypt(operation: CCOperation(kCCDecrypt),
                              key: decryptKey, iv: iv, input: body)
    }

    /// Constant-time compare so a bad MAC leaks nothing through timing.
    private func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    // MARK: AES-CBC

    /// AES-256-CBC with PKCS#7.
    ///
    /// Padding is applied and validated here rather than by `CCCrypt`'s
    /// `kCCOptionPKCS7Padding`: that option accepts inputs which are not a
    /// multiple of the block size and quietly returns garbage instead of an
    /// error, which is how malformed ciphertext used to reach the protobuf
    /// parser as noise. Doing it explicitly lets us reject it up front.
    private static func crypt(operation: CCOperation, key: SymmetricKey,
                              iv: Data, input: Data) throws -> Data {
        let blockSize = kCCBlockSizeAES128
        let padded: Data
        if operation == CCOperation(kCCEncrypt) {
            let padValue = blockSize - (input.count % blockSize)   // always 1...16
            padded = input + Data(repeating: UInt8(padValue), count: padValue)
        } else {
            guard !input.isEmpty, input.count % blockSize == 0 else {
                throw QuickShareError.protocolViolation("ciphertext is not block-aligned")
            }
            padded = input
        }

        let keyBytes = key.withUnsafeBytes { [UInt8]($0) }
        guard keyBytes.count == kCCKeySizeAES256 else {
            throw QuickShareError.internalFailure("wrong AES key size")
        }

        var output = [UInt8](repeating: 0, count: padded.count + blockSize)
        var moved = 0
        let status = padded.withUnsafeBytes { inPtr in
            iv.withUnsafeBytes { ivPtr in
                CCCrypt(operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(0),                  // no padding option; handled above
                        keyBytes, keyBytes.count,
                        ivPtr.baseAddress,
                        inPtr.baseAddress, padded.count,
                        &output, output.count,
                        &moved)
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else {
            throw QuickShareError.protocolViolation("AES operation failed (\(status))")
        }
        var result = Data(output.prefix(moved))

        if operation == CCOperation(kCCDecrypt) {
            result = try stripPKCS7(result, blockSize: blockSize)
        }
        return result
    }

    private static func stripPKCS7(_ data: Data, blockSize: Int) throws -> Data {
        guard let pad = data.last.map(Int.init), pad >= 1, pad <= blockSize, data.count >= pad else {
            throw QuickShareError.protocolViolation("invalid PKCS#7 padding")
        }
        // Every padding byte must carry the same value.
        guard data.suffix(pad).allSatisfy({ Int($0) == pad }) else {
            throw QuickShareError.protocolViolation("invalid PKCS#7 padding")
        }
        return Data(data.dropLast(pad))
    }
}

extension Data {
    /// Cryptographically secure random bytes.
    static func secureRandom(count: Int) -> Data {
        guard count > 0 else { return Data() }
        // SystemRandomNumberGenerator is documented as cryptographically secure
        // on Apple platforms and, unlike SecRandomCopyBytes, gives us no status
        // code to mishandle. Drawn 64 bits at a time rather than per byte.
        var rng = SystemRandomNumberGenerator()
        let words = (0..<((count + 7) / 8)).map { _ in rng.next() as UInt64 }
        return words.withUnsafeBytes { Data($0.prefix(count)) }
    }
}
