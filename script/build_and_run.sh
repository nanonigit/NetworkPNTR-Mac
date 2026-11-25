#!/bin/bash
set -euo pipefail
MODE="${1:-run}"
case "$MODE" in run|--verify|--build-only|--release-build-only|--debug|--logs|--telemetry) ;; *) echo 'Usage: build_and_run.sh [--verify|--build-only|--release-build-only|--debug|--logs|--telemetry]' >&2; exit 2;; esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ "$(uname -m)" == arm64 ]] || { echo 'Phase 1 currently supports Apple Silicon only.' >&2; exit 1; }
VARIANT="${NETWORKPNTR_MAC_VARIANT:-default}"
case "$VARIANT" in
  default) APP_NAME='NetworkPNTR Mac'; APP_ID='com.nanonigit.artex-mac'; DEFAULT_GUEST="$ROOT_DIR/guest/native-session-artifacts"; RUN_ARGS=() ;;
  cloud-preview) APP_NAME='NetworkPNTR Mac Cloud Preview'; APP_ID='com.nanonigit.networkpntr-mac.cloud-preview'; DEFAULT_GUEST="$ROOT_DIR/guest/native-session-cloud-artifacts"; RUN_ARGS=(--cloud-egress) ;;
  *) echo 'NETWORKPNTR_MAC_VARIANT must be default or cloud-preview.' >&2; exit 2 ;;
esac
APP="$ROOT_DIR/dist/$APP_NAME.app"
CONFIGURATION=debug
if [[ "$MODE" == --release-build-only ]]; then
  CONFIGURATION=release
  mkdir -p "$ROOT_DIR/dist/release"
  RELEASE_DIR="$(mktemp -d "$ROOT_DIR/dist/release/candidate.XXXXXXXX")"
  trap 'rm -rf -- "$RELEASE_DIR"' EXIT
  APP="$RELEASE_DIR/$APP_NAME.app"
fi
GUEST_BUILD_DIR="${NETWORKPNTR_MAC_GUEST_BUILD_DIR:-${ARTEX_MAC_GUEST_BUILD_DIR:-$DEFAULT_GUEST}}"
if [[ ! -f "$GUEST_BUILD_DIR/manifest.json" ]]; then
  echo 'Build the pinned native-session guest first; see docs/local-session-design.md.' >&2
  exit 1
fi
python3 "$ROOT_DIR/script/local_session_packaging.py" "$GUEST_BUILD_DIR" "$APP" "$VARIANT"
python3 "$ROOT_DIR/script/skill_overrides.py" --verify "$GUEST_BUILD_DIR/manifest.json"
if [[ "$CONFIGURATION" == debug ]] && { pgrep -x NetworkPNTRMac >/dev/null || pgrep -x ArtexMac >/dev/null; }; then
  echo 'Quit NetworkPNTR Mac normally before replacing its bundle so its VM can flush and stop.' >&2
  exit 1
fi
python3 "$ROOT_DIR/script/export_localizations.py" --check
swift build --configuration "$CONFIGURATION"
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
bash "$ROOT_DIR/script/build_app_icon.sh"
# Remove only this project's generated app bundle.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Guest"
cp "$BIN_DIR/NetworkPNTRMac" "$APP/Contents/MacOS/NetworkPNTRMac"
cp "$BIN_DIR/NetworkPNTRMCP" "$APP/Contents/MacOS/NetworkPNTRMCP"
codesign --force --sign - "$APP/Contents/MacOS/NetworkPNTRMCP"
codesign --verify --strict "$APP/Contents/MacOS/NetworkPNTRMCP"
cp -R "$BIN_DIR/NetworkPNTRMac_NetworkPNTRCore.bundle" "$APP/Contents/Resources/"
cp "$ROOT_DIR/.build-cache/branding/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$GUEST_BUILD_DIR/Image" "$GUEST_BUILD_DIR/initramfs.cpio.gz" "$GUEST_BUILD_DIR/manifest.json" "$GUEST_BUILD_DIR/system.ext4" "$APP/Contents/Resources/Guest/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NetworkPNTRMac</string>
<key>CFBundleIdentifier</key><string>$APP_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>NetworkPNTRRuntimeVariant</key><string>$VARIANT</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --entitlements guest/entitlements.plist "$APP"
codesign --verify --strict "$APP"
case "$MODE" in
  --release-build-only) trap - EXIT; printf 'Release candidate: %s\n' "$APP" ;;
  --build-only) exit 0 ;;
  --debug) lldb -- "$APP/Contents/MacOS/NetworkPNTRMac" "${RUN_ARGS[@]}" ;;
  run) /usr/bin/open -n "$APP" --args "${RUN_ARGS[@]}" ;;
  --verify) /usr/bin/open -n "$APP" --args "${RUN_ARGS[@]}"; sleep 2; pgrep -x NetworkPNTRMac >/dev/null ;;
  --logs|--telemetry) /usr/bin/open -n "$APP" --args "${RUN_ARGS[@]}"; /usr/bin/log stream --info --style compact --predicate 'process == "NetworkPNTRMac"' ;;
esac
