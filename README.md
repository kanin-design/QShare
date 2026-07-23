# QShare

A native macOS app for **Quick Share** (Google's Nearby Share) — send and receive
files to/from nearby Android devices over Wi-Fi LAN.

The **real Quick Share protocol engine is wired in** (vendored from NearDrop as
`NearbyShareKit`): mDNS discovery/advertising, UKEY2 handshake, and payload
transfer. A **mock engine** is still available for UI work without an Android
device (`QS_MOCK=1`).

## Layout

```
QuickShare2/
├── App/                     ← native SwiftUI app (Swift package)
│   └── Sources/
│       ├── QuickShare/      the app: App/, Models/, Services/, Views/, Design/
│       └── NearbyShareKit/  vendored Quick Share protocol engine (from NearDrop)
├── Resources/
│   └── NearDrop/            ← provenance: PROTOCOL.md (spec) + UNLICENSE
├── docs/
│   └── ARCHITECTURE.md      design + engine integration notes
└── ATTRIBUTION.md           credits for NearDrop and dependencies
```

## Run it

Real networking (Bonjour/mDNS) needs a proper app bundle so macOS can grant
local-network access — a bare `swift run` binary can't get it. Use the packager:

```bash
cd App
./Packaging/build-app.sh          # builds build/QuickShare2.app (release)
open build/QuickShare2.app
```

For **UI work without an Android device**, run the mock engine directly:

```bash
cd App
QS_MOCK=1 swift run QuickShare     # simulated devices, PINs, progress
# or open in Xcode:  open Package.swift
```

Requires macOS 14+ and a recent Swift toolchain (built with Swift 6.3 / Xcode 26).

## CLI / automation (`qshare`)

The running app hosts a localhost JSON API on `127.0.0.1:47821`, guarded by a
token in `~/.config/qshare/token`. The `qshare` CLI (or any tool/AI) drives it.

```bash
# install the CLI (app must be running for it to work):
ln -s "$(pwd)/App/Packaging/qshare" /usr/local/bin/qshare

qshare list                                  # visible devices (★ = trusted)
qshare list --json                           # machine-readable
qshare send ~/photo.jpg --to "Noise's phone" # blocks until sent; exit 0 on success
qshare status
qshare --help
```

Raw API (for AI/other languages): `GET /devices`, `GET /transfers`,
`POST /send {"paths":[…],"to":"…"}` — all with header
`Authorization: Bearer <token>`.

## Status

- [x] Research + protocol/prior-art review (see docs/ARCHITECTURE.md)
- [x] Native SwiftUI shell, minimal design, Send + Receive flows
- [x] Mock engine driving all UI states (`QS_MOCK=1`)
- [x] Vendor NearDrop's `NearbyShare/` protocol core → `NearbyShareKit` target
- [x] Real engine wrapper (`NearbyQuickShareService`) — discovery, advertise,
      handshake, send, receive, in-app progress (incoming progress hook added)
- [x] `.app` bundle with Bonjour + local-network Info.plist
- [x] End-to-end verified against a real Android device (send + receive)
- [x] Path-traversal hardening on incoming file names
- [x] App icon (native squircle)
- [x] Menu-bar presence (stays alive in the background)
- [x] Remembered/trusted devices (auto-accept from chosen senders)
- [ ] User notifications for incoming requests while the window is closed
- [ ] Finder share extension (share sheet entry point)
- [ ] Configurable receive location (currently ~/Downloads, like NearDrop)
- [ ] Further frame-parser hardening / fuzzing
```
