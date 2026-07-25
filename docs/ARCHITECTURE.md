# Architecture

## Goal

Native macOS app to send/receive files with Android via **Quick Share** (Nearby
Share) over Wi-Fi LAN. All-Swift, **no third-party dependencies** — the protocol
is implemented here on Foundation, Network and CryptoKit alone. The protocol
itself was reverse-engineered by [grishka/NearDrop](https://github.com/grishka/NearDrop);
see ATTRIBUTION.md.

## Layering

The app is a thin, testable SwiftUI shell over a swappable engine:

```
Views (SwiftUI)  ──observe──▶  AppModel (@MainActor, ObservableObject)
                                   │  intents (connect, sendFiles, respond…)
                                   ▼
                          QuickShareService  (protocol)
                          ├── MockQuickShareService   ← QS_MOCK=1 (simulated)
                          └── NearbyQuickShareService ← wraps NearDrop (default)
                                   │
                                   ▼ callbacks (QuickShareServiceDelegate, @MainActor)
                              back into AppModel
```

**Why a protocol seam:** the UI never touches sockets, protobufs, or crypto. It
depends only on `QuickShareService` + `QuickShareServiceDelegate`. Swapping the
mock for the real engine changes one line in `AppModel.init` and adds no UI
churn.

### Files

| File | Role |
|------|------|
| `App/QuickShareApp.swift` | `@main`, window, `AppDelegate` (activation for `swift run`) |
| `App/AppModel.swift` | Single source of truth; state machine; delegate impl |
| `Services/QuickShareService.swift` | Engine interface + delegate |
| `Services/MockQuickShareService.swift` | Simulated engine for the dummy build |
| `Models/RemoteDevice.swift` | Peer device (mirrors NearDrop `RemoteDeviceInfo`) |
| `Models/TransferModels.swift` | `FileItem`, `IncomingRequest`, `ActiveTransfer`, phases |
| `Views/RootView.swift` | Shell: header, Send/Receive switch, transfers list |
| `Views/SendView.swift` | Discover → connect → PIN → drag-drop/picker → send |
| `Views/ReceiveView.swift` | Visibility toggle, QR code, accept/decline |
| `Views/Components/*` | DeviceRow, DropZone, QRCode, TransferRow, PinBadge, … |
| `Design/Theme.swift` | Design tokens + `Card` container |

## The protocol interface (designed to match NearDrop)

`QuickShareService` deliberately mirrors NearDrop's two delegate groups so the
real wrapper is mechanical:

| Our method / callback | NearDrop equivalent |
|---|---|
| `startAdvertising` / `stopAdvertising` | `NearbyConnectionManager.becomeVisible` / listener |
| `serviceDidReceiveIncomingRequest` + `respondToIncoming` | `MainAppDelegate.obtainUserConsent` + `submitUserConsent` |
| `startDiscovery` / `stopDiscovery` | `startDeviceDiscovery` / `stopDeviceDiscovery` |
| `serviceDidDiscover` / `serviceDidLose` | `ShareExtensionDelegate.addDevice` / `removeDevice` |
| `connect(to:)` → `serviceDidEstablishConnection(pin:)` | outbound connection → `connectionWasEstablished(pinCode:)` |
| `sendFiles` | `OutboundNearbyConnection` |
| `serviceDidUpdateProgress` / `serviceDidFinishTransfer` | `transferProgress` / `transferFinished` |

## Protocol facts (from NearDrop's PROTOCOL.md)

- **Discovery:** mDNS service type `_FC9F5ED42C8A._tcp.`, TXT `n=` base64 endpoint info.
- **Transport:** TCP, 4-byte big-endian length-prefixed protobuf frames.
- **Handshake:** UKEY2 (ECDSA P-256), HKDF-SHA256 → 4 keys, yields a 4-digit PIN.
- **Encryption:** AES-256-CBC + HMAC-SHA256 "secure messages".
- **Transfer:** PairedKeyEncryption → Introduction (file list) → Accept/Reject →
  payload chunks → keep-alives every 10s.

## Known platform constraint

macOS can't emit the BLE advertisements Android uses for automatic discovery.
So Mac→Android generally works, but Android auto-seeing the Mac needs same Wi-Fi
+ often the QR/manual path. This is inherent, not fixable in our code — the UI is
designed around it (explicit visibility toggle + QR on the Receive screen).

## Send-flow semantics (important)

Quick Share has no "connect, then later choose files" step — the UKEY2 handshake
happens *when files are offered*. So `sendFiles(_:to:)` is connect+offer in one
call, and the verification PIN only exists afterwards. The UI reflects this:

`idle` → pick device → `staging` (drop zone / picker) → **Send** →
`connecting` → `awaitingConsent` (PIN shown) → remote accepts →
transfer moves to the shared Transfers list.

`NearbyConnectionManager` gives idless callbacks per outbound transfer, so
`NearbyQuickShareService` passes a fresh `OutboundHandle` (carrying the transfer
id + device) as the delegate for each send.

## The protocol layer

`Sources/QuickShareProtocol/` is ours end to end. No generated code, no external
packages.

| Area | Files | Notes |
|---|---|---|
| Wire format | `Wire/ProtoWire.swift` | Hand-written proto2 reader/writer. Bounds-checked, varints capped, length prefixes validated against remaining bytes *before* allocating, depth-limited, unknown fields skipped rather than retained. |
| Messages | `Messages/*.swift` | The ~32 messages the protocol actually exchanges, replacing 15,436 lines of generated code. |
| Crypto | `Crypto/*.swift` | UKEY2 key agreement on CryptoKit P-256; AES-256-CBC + HMAC-SHA256 envelope. |
| Transport | `Transport/*.swift` | Actor-isolated async framing and the two session state machines. |
| Discovery | `Discovery/*.swift` | mDNS advertise/browse, endpoint info, QR path. |

Two details are load-bearing and easy to get wrong; both are pinned by tests.

**Shared-secret encoding.** The key schedule hashes the ECDH X coordinate as a
*magnitude* — leading zeros stripped. CryptoKit returns a fixed 32 bytes. Using
it directly makes the two peers derive different keys whenever X starts with a
zero byte, roughly 1 handshake in 256. `UKey2.magnitudeBytes` reproduces the
reference behaviour; `CryptoVectors` holds cases cross-checked against the
original implementation, including the divergent ones.

**Public-key validation.** `P256.KeyAgreement.PublicKey(rawRepresentation:)`
does *not* check that the point is on the curve — it accepts all-zero and
arbitrary coordinates. Peer keys go through the X9.63 initialiser, which does
validate, closing an invalid-curve attack on the handshake.

## Wire compatibility

The protocol is undocumented, so "correct" means "byte-identical to something
that demonstrably worked". Before the protobuf dependency was removed, every
message was serialized with it and the bytes captured as `GoldenFixtures`. Each
type must encode to exactly those bytes and round-trip them. Regenerating them
requires temporarily restoring the dependency, which should not be necessary
unless the protocol itself changes.

That covers the wire format and the key schedule. It does **not** prove
interoperability with a real Android device — only a live transfer does.

## Status / next

Done: vendored engine (`NearbyShareKit`), `NearbyQuickShareService` wrapper,
`.app` bundle with Bonjour + `NSLocalNetworkUsageDescription` (`Packaging/`),
end-to-end verification against a real Android device, menu-bar item, transfer
history, configurable receive location.

Next:
1. **Smoke-test against a real Android device**, both directions. The rewrite is
   covered by 117 tests but has not yet moved a byte to a phone.
2. **Finder share extension** as a second entry point.
3. **Verifiable device identity.** Auto-accept is deliberately absent because
   there is nothing to key it on — see *Device identity* below.
4. **Quarantine received files** so Gatekeeper treats them as downloaded.

## Device identity (why there is no auto-accept)

Trust needs a name you can verify, and this implementation has none:

- The UKEY2 ECDSA keys are generated per handshake
  (`domain.makeKeyPair()` in `InboundNearbyConnection.processUkey2ClientInit`),
  so a peer-key fingerprint changes every connection.
- The paired-key frames that carry persistent identity in real Quick Share are
  stubbed: NearDrop sends random bytes for `secretIDHash`/`signedData` and always
  answers `pairedKeyResult = .unable`.
- Inbound `RemoteDeviceInfo` carries no id at all — only the remote-supplied,
  unauthenticated display name.

So the app always prompts. `knownDevices` records names you've accepted from and
is used purely as a hint on the prompt. Re-enabling auto-accept safely means
implementing the certificate/contact exchange first.

## Security notes

The network-facing parser is the main attack surface. Before any real build ships:
validate all length prefixes/offsets, bound allocations, and fuzz the protobuf
decoders. Never trust file names/paths from the introduction frame (path
traversal) — sanitize and confine writes to the chosen downloads directory.
