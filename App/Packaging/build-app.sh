#!/usr/bin/env bash
# Build QuickShare2.app — a proper macOS bundle so the OS grants local-network
# access (Bonjour/mDNS) that a bare `swift run` binary can't get.
#
# Usage: App/Packaging/build-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$HERE")"                 # .../App
OUT="$APP_DIR/build/QuickShare2.app"

echo "▶︎ Building ($CONFIG)…"
( cd "$APP_DIR" && swift build -c "$CONFIG" )

BIN="$(cd "$APP_DIR" && swift build -c "$CONFIG" --show-bin-path)/QuickShare"

echo "▶︎ Assembling $OUT…"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/QuickShare"
cp "$HERE/Info.plist" "$OUT/Contents/Info.plist"
cp "$HERE/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$OUT/Contents/PkgInfo"

# Ad-hoc codesign so the local-network TCC prompt has a stable identity.
codesign --force --deep --sign - "$OUT" >/dev/null 2>&1 || \
    echo "  (codesign skipped — app will still run, may re-prompt for network)"

echo "✓ Built $OUT"
echo "  Run it:  open \"$OUT\""
