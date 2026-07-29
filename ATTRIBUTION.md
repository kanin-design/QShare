# Attribution

QShare's protocol implementation is original code, but it stands on prior
open-source reverse-engineering work. Credit where it is due.

## NearDrop — protocol reverse engineering

Google's Quick Share / Nearby Share LAN protocol is undocumented. It was
reverse-engineered and written up by **@grishka**, whose specification and
implementation are published at
**[grishka/NearDrop](https://github.com/grishka/NearDrop)** and released into
the public domain under The Unlicense.

QShare implements the protocol **from that specification**.
`App/Sources/QuickShareProtocol/` is written against it rather than derived from
it, and no NearDrop source is present in this repository. The specification
leaves some behaviour implicit — field ordering, the paired-key placeholders,
the PIN derivation — and NearDrop's implementation was the behavioural reference
for those details.

The Unlicense imposes no conditions, so this credit is given because it is
deserved, not because it is required. Without that work this app would not
exist.

## Protobuf schemas

The message definitions descend from Google's `securemessage.proto`,
`securegcm.proto`, `ukey.proto`, `offline_wire_formats.proto` and
`wire_format.proto` (Apache-2.0). QShare does not vendor the generated code; it
implements by hand only the ~32 messages the protocol actually exchanges.

## Dependencies

None. QShare builds against Foundation, Network, CryptoKit, CommonCrypto,
AppKit and SwiftUI — all part of macOS.
