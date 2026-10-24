#!/bin/bash
set -euo pipefail
MODE="${1:-run}"
case "$MODE" in run|--verify|--build-only|--debug|--logs|--telemetry) ;; *) echo 'Usage: build_and_run.sh [--verify|--build-only|--debug|--logs|--telemetry]' >&2; exit 2;; esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ "$(uname -m)" == arm64 ]] || { echo 'Phase 1 currently supports Apple Silicon only.' >&2; exit 1; }
GUEST_BUILD_DIR="${ARTEX_MAC_GUEST_BUILD_DIR:-$ROOT_DIR/guest/backend-artifacts}"
if [[ ! -f "$GUEST_BUILD_DIR/manifest.json" ]]; then
  echo 'Build the pinned backend guest first: python3 script/prepare_backend.py --source /path/to/pinned/artex-global' >&2
  exit 1
fi
if pgrep -x ArtexMac >/dev/null; then
  echo 'Quit ARTEX Mac normally before replacing its bundle so its VM can flush and stop.' >&2
  exit 1
fi
python3 "$ROOT_DIR/script/export_localizations.py" --check
swift build
BIN_DIR="$(swift build --show-bin-path)"
APP="$ROOT_DIR/dist/ARTEX Mac.app"
# Remove only this project's generated app bundle.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Guest"
cp "$BIN_DIR/ArtexMac" "$APP/Contents/MacOS/ArtexMac"
for bundle in "$BIN_DIR"/*.bundle; do
  [[ -d "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done
cp "$GUEST_BUILD_DIR/Image" "$GUEST_BUILD_DIR/initramfs.cpio.gz" "$GUEST_BUILD_DIR/manifest.json" "$GUEST_BUILD_DIR/system.ext4" "$APP/Contents/Resources/Guest/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ArtexMac</string>
<key>CFBundleIdentifier</key><string>com.nanonigit.artex-mac</string>
<key>CFBundleName</key><string>ARTEX Mac</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --entitlements guest/entitlements.plist "$APP"
codesign --verify --strict "$APP"
case "$MODE" in
  --build-only) exit 0 ;;
  --debug) lldb -- "$APP/Contents/MacOS/ArtexMac" ;;
  run) /usr/bin/open -n "$APP" ;;
  --verify) /usr/bin/open -n "$APP"; sleep 2; pgrep -x ArtexMac >/dev/null ;;
  --logs|--telemetry) /usr/bin/open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "ArtexMac"' ;;
esac
