#!/usr/bin/env bash
# Build QShare.app — a proper macOS bundle so the OS grants local-network
# access (Bonjour/mDNS) that a bare `swift run` binary can't get.
#
# Usage: App/Packaging/build-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$HERE")"                 # .../App
OUT="$APP_DIR/build/QShare.app"

echo "▶︎ Building ($CONFIG)…"
( cd "$APP_DIR" && swift build -c "$CONFIG" )

BIN="$(cd "$APP_DIR" && swift build -c "$CONFIG" --show-bin-path)/QuickShare"

# --- build identity -----------------------------------------------------
# A monotonic counter so it's obvious at a glance which build is running, plus
# the commit and timestamp, which are what actually pin it down. The counter
# lives outside git (it would conflict on every branch); the commit does not.
COUNTER_FILE="$HERE/.build-number"
BUILD_NUMBER=$(( $(cat "$COUNTER_FILE" 2>/dev/null || echo 34000) + 1 ))
echo "$BUILD_NUMBER" > "$COUNTER_FILE"

GIT_COMMIT="$(git -C "$APP_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git -C "$APP_DIR" diff --quiet HEAD 2>/dev/null; then
    GIT_COMMIT="$GIT_COMMIT+dirty"
fi
BUILD_DATE="$(date '+%Y-%m-%d %H:%M')"

echo "▶︎ Assembling $OUT…"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/QShare"
cp "$HERE/Info.plist" "$OUT/Contents/Info.plist"
cp "$HERE/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$OUT/Contents/PkgInfo"

PLIST="$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :QSGitCommit $GIT_COMMIT" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :QSBuildDate $BUILD_DATE" "$PLIST"

# Ad-hoc codesign so the local-network TCC prompt has a stable identity.
codesign --force --deep --sign - "$OUT" >/dev/null 2>&1 || \
    echo "  (codesign skipped — app will still run, may re-prompt for network)"

echo "✓ Built $OUT"
echo "  BUILD $BUILD_NUMBER · $GIT_COMMIT · $BUILD_DATE"
echo "  Run it:  open \"$OUT\""
