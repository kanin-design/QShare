import XCTest
import CryptoKit
import SwiftECC
import BigInt
@testable import QuickShareProtocol

/// Cross-validates the CryptoKit key agreement against SwiftECC — the stack the
/// reference implementation used — while that dependency is still present, and
/// emits the agreeing cases as permanent test vectors.
///
/// The case worth catching: SwiftECC returns the ECDH X coordinate as a
/// *magnitude* (leading zeros stripped) while CryptoKit returns a fixed 32
/// bytes. Those disagree roughly 1 handshake in 256. This sweeps enough random
/// key pairs to hit it.
final class GenerateCryptoVectors: XCTestCase {

    /// Reference path: SwiftECC ECDH exactly as the vendored engine did it.
    private func referenceDHS(privateScalar: BInt, peerX: Data, peerY: Data) throws -> Data {
        let domain = Domain.instance(curve: .EC256r1)
        let peer = try ECPublicKey(domain: domain,
                                   w: Point(BInt(magnitude: [UInt8](peerX)),
                                            BInt(magnitude: [UInt8](peerY))))
        let product = try domain.multiplyPoint(peer.w, privateScalar)
        return Data(product.x.asMagnitudeBytes())
    }

    func testAgreementMatchesReferenceAndEmitVectors() throws {
        let domain = Domain.instance(curve: .EC256r1)
        var vectors: [String] = []
        var shortSecrets = 0
        let rounds = 400

        for _ in 0..<rounds {
            // Our side: CryptoKit. Their side: SwiftECC.
            let ourPrivate = P256.KeyAgreement.PrivateKey()
            let (peerPub, peerPriv) = domain.makeKeyPair()

            let peerX = Data(peerPub.w.x.asMagnitudeBytes())
            let peerY = Data(peerPub.w.y.asMagnitudeBytes())

            // CryptoKit path (what we ship).
            var wire = EcP256PublicKey()
            wire.x = peerX
            wire.y = peerY
            let peerKey = try UKey2.publicKey(from: wire)
            let shared = try ourPrivate.sharedSecretFromKeyAgreement(with: peerKey)
            let ours = UKey2.magnitudeBytes(shared.withUnsafeBytes { Data($0) })

            // Reference path, same inputs: our public key as SwiftECC sees it.
            let ourRaw = ourPrivate.publicKey.rawRepresentation
            let theirs = try referenceDHS(privateScalar: peerPriv.s,
                                          peerX: Data(ourRaw.prefix(32)),
                                          peerY: Data(ourRaw.suffix(32)))

            XCTAssertEqual(ours.hexString, theirs.hexString,
                           "ECDH disagreed with the reference implementation")
            if ours.count < 32 { shortSecrets += 1 }

            // Capture a vector: our private key, peer public key, expected secret.
            let priv = ourPrivate.rawRepresentation.hexString
            vectors.append("""
                    Vector(privateKey: "\(priv)",
                           peerX: "\(peerX.hexString)",
                           peerY: "\(peerY.hexString)",
                           expectedSharedMagnitude: "\(ours.hexString)"),
            """)
        }

        print("CRYPTO-VECTORS rounds=\(rounds) shortSecrets=\(shortSecrets)")
        XCTAssertGreaterThan(shortSecrets, 0,
                             "no leading-zero secrets were generated; the vector set would not cover the divergent case")

        let src = """
        // GENERATED — ECDH vectors cross-checked against SwiftECC before that
        // dependency was removed. `expectedSharedMagnitude` is the *magnitude*
        // encoding (leading zeros stripped), which is what the key schedule
        // hashes. Do not edit by hand.

        struct Vector {
            let privateKey: String
            let peerX: String
            let peerY: String
            let expectedSharedMagnitude: String
        }

        enum CryptoVectors {
            static let all: [Vector] = [
        \(vectors.joined(separator: "\n"))
            ]
        }

        """
        let dest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuickShareProtocolTests/CryptoVectors.swift")
        try src.write(to: dest, atomically: true, encoding: .utf8)
        print("WROTE crypto vectors -> \(dest.path)")
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
