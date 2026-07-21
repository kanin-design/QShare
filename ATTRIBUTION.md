# Attribution

QuickShare2 builds on prior open-source work. Thanks to the authors below.

## NearDrop — the Quick Share protocol engine

`App/Sources/NearbyShareKit/` is vendored and adapted from
**[grishka/NearDrop](https://github.com/grishka/NearDrop)**, which
reverse-engineered Google's Nearby Share / Quick Share LAN protocol (UKEY2
handshake, secure messages, mDNS discovery, payload transfer).

NearDrop is released into the public domain under **The Unlicense** — see
[`Resources/NearDrop/UNLICENSE`](Resources/NearDrop/UNLICENSE). The protocol
write-up is preserved at [`Resources/NearDrop/PROTOCOL.md`](Resources/NearDrop/PROTOCOL.md).

Our changes to the vendored copy are marked with `// QuickShare2` comments and
summarized in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (incoming-progress
and saved-file hooks, visibility toggle, and a path-traversal fix).

## Dependencies

Resolved via Swift Package Manager:

- **[apple/swift-protobuf](https://github.com/apple/swift-protobuf)** — Apache-2.0
- **[leif-ibsen/SwiftECC](https://github.com/leif-ibsen/SwiftECC)** — MIT
- **[leif-ibsen/BigInt](https://github.com/leif-ibsen/BigInt)** — MIT

(SwiftECC additionally pulls in ASN1 and BigInt, all by the same author, MIT.)
