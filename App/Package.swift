// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickShare",
    platforms: [.macOS("26.0")],   // real Liquid Glass (glassEffect) needs macOS 26
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.21.0"),
        .package(url: "https://github.com/leif-ibsen/SwiftECC", from: "3.5.0"),
        .package(url: "https://github.com/leif-ibsen/BigInt", from: "1.9.0"),
    ],
    targets: [
        // Vendored Quick Share protocol engine (reverse-engineered by NearDrop,
        // grishka/NearDrop, public domain). Handles mDNS, UKEY2 handshake,
        // secure messages and payload transfer. See Resources/NearDrop.
        .target(
            name: "NearbyShareKit",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftECC", package: "SwiftECC"),
                .product(name: "BigInt", package: "BigInt"),
            ],
            path: "Sources/NearbyShareKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Our own Quick Share protocol implementation. No third-party
        // dependencies — Foundation, Network and CryptoKit only.
        .target(
            name: "QuickShareProtocol",
            path: "Sources/QuickShareProtocol",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Our native SwiftUI app.
        .executableTarget(
            name: "QuickShare",
            dependencies: ["NearbyShareKit"],
            path: "Sources/QuickShare",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Temporary: uses swift-protobuf as an oracle to emit golden wire bytes
        // for the hand-written codec. Deleted along with the dependency.
        .testTarget(
            name: "FixtureGen",
            dependencies: [
                "NearbyShareKit",
                "QuickShareProtocol",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftECC", package: "SwiftECC"),
                .product(name: "BigInt", package: "BigInt"),
            ],
            path: "Tests/FixtureGen",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NearbyShareKitTests",
            dependencies: ["NearbyShareKit"],
            path: "Tests/NearbyShareKitTests",
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
            dependencies: ["QuickShare"],
            path: "Tests/QuickShareTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
