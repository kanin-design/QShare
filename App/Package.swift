// swift-tools-version: 6.0
import PackageDescription

// No third-party dependencies. The Quick Share protocol — wire format, UKEY2
// handshake, secure messages, mDNS discovery and payload transfer — is
// implemented in QuickShareProtocol on top of Foundation, Network and CryptoKit
// alone. See docs/ARCHITECTURE.md.
let package = Package(
    name: "QuickShare",
    platforms: [.macOS("26.0")],   // real Liquid Glass (glassEffect) needs macOS 26
    targets: [
        // Our Quick Share protocol implementation.
        .target(
            name: "QuickShareProtocol",
            path: "Sources/QuickShareProtocol",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Our native SwiftUI app.
        .executableTarget(
            name: "QuickShare",
            dependencies: ["QuickShareProtocol"],
            path: "Sources/QuickShare",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "QuickShareProtocolTests",
            dependencies: ["QuickShareProtocol"],
            path: "Tests/QuickShareProtocolTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "QuickShareTests",
            dependencies: ["QuickShare", "QuickShareProtocol"],
            path: "Tests/QuickShareTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
