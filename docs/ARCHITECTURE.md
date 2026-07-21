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
                          ├── MockQuickShareService   ← ships today (simulated)
                          └── NearbyQuickShareService ← wraps NearDrop (to build)
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
  path component and destinations are confined to `~/Downloads` (upstream wrote
  `downloads.appendingPathComponent(file.name)` with the raw remote name).
- `NearbyConnectionManager.becomeInvisible()` + `becomeVisible()` listener
  recreation, so advertising can actually be toggled off and back on.

## Status / next

Done: vendored engine (`NearbyShareKit`), `NearbyQuickShareService` wrapper,
`.app` bundle with Bonjour + `NSLocalNetworkUsageDescription` (`Packaging/`).

Next:
1. **Verify end-to-end** against a real Android device (send + receive).
2. **Harden** the frame/protobuf parser (untrusted network input — see the
   *Protocol Prying* paper and SafeBreach's Quick Share RCE writeup).
3. **Grow UX:** menu-bar item, Finder share extension, transfer history,
   configurable received-files location (currently ~/Downloads).

## Security notes

The network-facing parser is the main attack surface. Before any real build ships:
validate all length prefixes/offsets, bound allocations, and fuzz the protobuf
decoders. Never trust file names/paths from the introduction frame (path
traversal) — sanitize and confine writes to the chosen downloads directory.
