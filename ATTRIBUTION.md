# Attribution

QShare's protocol implementation is original code, but it stands on prior
open-source reverse-engineering work. Credit where it is due.

## NearDrop — protocol reverse engineering

Google's Quick Share / Nearby Share LAN protocol is undocumented. It was
reverse-engineered by **[grishka/NearDrop](https://github.com/grishka/NearDrop)**,
released into the public domain under **The Unlicense**. The protocol write-up
is preserved at [`Resources/NearDrop/PROTOCOL.md`](Resources/NearDrop/PROTOCOL.md)
alongside [`Resources/NearDrop/UNLICENSE`](Resources/NearDrop/UNLICENSE).

QShare originally vendored NearDrop's Swift implementation. It no longer does:
`App/Sources/QuickShareProtocol/` is a clean reimplementation written against
the protocol description, using NearDrop's code as a behavioural reference for
the parts the write-up leaves implicit (field ordering, the paired-key
placeholders, the PIN derivation). No NearDrop source remains in this
repository.

The Unlicense imposes no conditions, so this credit is given because it is
deserved, not because it is required.

## Protobuf schemas

The message definitions descend from Google's `securemessage.proto`,
`securegcm.proto`, `ukey.proto`, `offline_wire_formats.proto` and
`wire_format.proto` (Apache-2.0). QShare does not vendor the generated code; it
implements by hand only the ~32 messages the protocol actually exchanges.

## Dependencies

None. QShare builds against Foundation, Network, CryptoKit, CommonCrypto,
AppKit and SwiftUI — all part of macOS.
