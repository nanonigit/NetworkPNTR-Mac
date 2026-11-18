#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_SOURCE="$ROOT_DIR/assets/branding/networkpntr-app-icon.png"
ICON_OUTPUT="${1:-$ROOT_DIR/.build-cache/branding/AppIcon.icns}"
[[ $# -le 1 ]] || { echo 'Usage: build_app_icon.sh [output.icns]' >&2; exit 2; }
[[ -f "$ICON_SOURCE" ]] || { echo 'Missing NetworkPNTR Mac icon master.' >&2; exit 1; }
ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/networkpntr-icon.XXXXXXXX")"
trap 'rm -rf "$ICON_WORK"' EXIT
mkdir "$ICON_WORK/AppIcon.iconset"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICON_WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  /usr/bin/sips -z "$retina" "$retina" "$ICON_SOURCE" --out "$ICON_WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$ICON_WORK/AppIcon.icns"
mkdir -p "$(dirname "$ICON_OUTPUT")"
cp "$ICON_WORK/AppIcon.icns" "$ICON_OUTPUT"
