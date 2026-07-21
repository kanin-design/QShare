// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickShare",
    platforms: [.macOS(.v15)],
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
        // Our native SwiftUI app.
        .executableTarget(
            name: "QuickShare",
            dependencies: ["NearbyShareKit"],
            path: "Sources/QuickShare",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
