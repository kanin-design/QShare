import Foundation
import CryptoKit

/// The QR path, for reaching a device that isn't visible in the discovery list.
///
/// We generate an ephemeral key and show it as a Quick Share App Link. A phone
/// that scans it starts advertising a token derived from the same key, which we
/// recognise while browsing — at which point the transfer proceeds normally.
public struct QRCodeSession: Sendable {

    /// The blob encoded into the QR link.
    public let keyData: Data
    /// What we watch for in a peer's advertisement.
    public let advertisingToken: Data
    /// Decrypts the device name an otherwise-invisible peer advertises.
    let nameEncryptionKey: SymmetricKey
    /// Signs the handshake so the peer can tie the connection to the scan.
    let signingKey: P256.Signing.PrivateKey

    /// Android only routes this exact URL form to Quick Share.
    public var url: String {
        "https://quickshare.google/qrcode#key=\(keyData.urlSafeBase64EncodedString())"
    }

    public init() {
        let signingKey = P256.Signing.PrivateKey()
        self.signingKey = signingKey

        // Prefix, then the public key's X coordinate.
        var blob = Data([0, 0, 2])
        let x = Data(signingKey.publicKey.rawRepresentation.prefix(32))
        // The signed encoding can carry a leading zero byte; Android rejects the
        // endpoint info outright if it survives, so keep only the low 32 bytes.
        blob.append(UKey2.signedBytes(x).suffix(32))
        self.keyData = blob

        let ikm = SymmetricKey(data: blob)
        self.advertisingToken = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: Data(),
            info: Data("advertisingContext".utf8), outputByteCount: 16)
            .withUnsafeBytes { Data($0) }
        self.nameEncryptionKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: Data(),
            info: Data("encryptionKey".utf8), outputByteCount: 16)
    }

    /// True when this advertisement is the device that scanned our code.
    public func matches(advertisedQRData data: Data) -> Bool {
        // Constant time isn't required — this is a public token, not a secret —
        // but the lengths must match before comparing.
        data.count == advertisingToken.count && data == advertisingToken
    }

    /// Decrypts the name an invisible peer advertises alongside its token.
    ///
    /// The token is the AEAD's associated data, so a name only decrypts if the
    /// peer really did derive it from our QR key.
    public func decryptDeviceName(from data: Data) -> String? {
        guard data.count > 28 else { return nil }
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let plaintext = try? AES.GCM.open(box, using: nameEncryptionKey,
                                                authenticating: advertisingToken) else {
            return nil
        }
        return String(data: plaintext, encoding: .utf8)
    }

    /// Signs the handshake's auth string so the peer can bind this connection to
    /// the code it scanned. Returned as raw r‖s, which is what the wire expects.
    public func handshakeSignature(authKey: SymmetricKey) -> Data? {
        let message = authKey.withUnsafeBytes { Data($0) }
        guard let signature = try? signingKey.signature(for: message) else { return nil }
        return signature.rawRepresentation
    }
}
