# Architecture

## Goal

Native macOS app to send/receive files with Android via **Quick Share** (Nearby
Share) over Wi-Fi LAN. Built all-Swift, reusing the reverse-engineered protocol
from [grishka/NearDrop](https://github.com/grishka/NearDrop) (public domain) as
the handshake/transfer foundation.

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

## Modifications to vendored code

Kept minimal and marked `// QuickShare2` in `Sources/NearbyShareKit`:
- `InboundNearbyConnection` / `NearbyConnectionManager`: added an **incoming
  progress** hook (upstream only publishes a system `NSProgress` per file) and a
  **saved-file-URLs** hook so the app can open/reveal received files.
- **Path-traversal fix**: remote-supplied file names are sanitized to a single
  path component and destinations are confined to the configured receive
  directory (upstream wrote `downloads.appendingPathComponent(file.name)` with
  the raw remote name).
- **Real visibility reporting**: `NetServiceDelegate` is actually implemented and
  a `visibilityDidChange` hook reports advertising state, so the UI can't claim
  to be visible when the listener failed or mDNS never published.
- **Listener lifecycle**: teardown is tracked with an explicit flag rather than
  polling the asynchronously-updated `NWListener.state`, and the listener is
  optional so a failed creation degrades instead of trapping.
- `NearbyConnectionManager.becomeInvisible()` + `becomeVisible()` listener
  recreation, so advertising can actually be toggled off and back on.

## Status / next

Done: vendored engine (`NearbyShareKit`), `NearbyQuickShareService` wrapper,
`.app` bundle with Bonjour + `NSLocalNetworkUsageDescription` (`Packaging/`),
end-to-end verification against a real Android device, menu-bar item, transfer
history, configurable receive location.

Next:
1. **Harden** the frame/protobuf parser (untrusted network input — see the
   *Protocol Prying* paper and SafeBreach's Quick Share RCE writeup).
2. **Finder share extension** as a second entry point.
3. **Verifiable device identity.** Auto-accept is deliberately absent because
   there is nothing to key it on — see *Device identity* below.

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
