#!/usr/bin/env bash
# Builds Palmo with SwiftPM and assembles a signed Palmo.app in ./build.
#
# Usage: scripts/build-app.sh [--debug] [--no-install] [--identity "Apple Development: …"]
#   By default the signed app is then installed to /Applications/Palmo.app
#   (quitting a running Palmo first and relaunching it afterwards). --no-install
#   leaves it in ./build only.
#   PALMO_SIGN_IDENTITY can also set the identity. Without one, the first
#   "Apple Development" identity in the keychain is used, falling back to ad-hoc ("-").
#   A stable identity matters: macOS ties Accessibility and Camera grants to the
#   signature, so ad-hoc builds lose those grants on every rebuild.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG=release
IDENTITY="${PALMO_SIGN_IDENTITY:-}"
INSTALL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG=debug; shift ;;
    --no-install) INSTALL=0; shift ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
done

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -n1)"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "warning: no Apple Development identity found; signing ad-hoc." >&2
  IDENTITY="-"
fi

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product Palmo
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Palmo.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Palmo" "$APP/Contents/MacOS/Palmo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Copy SwiftPM resource bundles, if any target ever declares resources.
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

echo "==> Signing with: $IDENTITY"
codesign --force --options runtime --timestamp=none \
  --entitlements Resources/Palmo.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "==> Built $(pwd)/$APP"

if [[ "$INSTALL" == 1 ]]; then
  DEST="/Applications/Palmo.app"
  WAS_RUNNING=0
  if pgrep -x Palmo >/dev/null; then
    WAS_RUNNING=1
    echo "==> Quitting running Palmo"
    osascript -e 'tell application id "com.kousic.palmo" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 50); do pgrep -x Palmo >/dev/null || break; sleep 0.1; done
    pkill -x Palmo 2>/dev/null || true
    sleep 0.3
  fi
  echo "==> Installing to $DEST"
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  codesign --verify --strict "$DEST"
  if [[ "$WAS_RUNNING" == 1 ]]; then
    echo "==> Relaunching $DEST"
    open "$DEST"
  fi
  echo "==> Installed $DEST"
fi
