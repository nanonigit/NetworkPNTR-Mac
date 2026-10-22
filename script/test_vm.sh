#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
python3 script/prepare_guest.py
swift build --product VMProbe
BIN_DIR="$(swift build --show-bin-path)"
codesign --force --sign - --entitlements guest/entitlements.plist "$BIN_DIR/VMProbe"
mkdir -p evidence/local/vm
python3 - <<'PY'
from pathlib import Path
import gzip, hashlib, json, shutil
source = Path('guest/artifacts')
target = Path('.build-cache/guest-no-ready')
target.mkdir(parents=True, exist_ok=True)
shutil.copyfile(source/'Image', target/'Image')
data = gzip.decompress((source/'initramfs.cpio.gz').read_bytes())
assert b'ARTEX_MAC_GUEST_READY' in data
data = gzip.compress(data.replace(b'ARTEX_MAC_GUEST_READY', b'ARTEX_MAC_GUEST_WAIT_'), mtime=0)
(target/'initramfs.cpio.gz').write_bytes(data)
manifest = json.loads((source/'manifest.json').read_text())
manifest['initramfsSHA256'] = hashlib.sha256(data).hexdigest()
(target/'manifest.json').write_text(json.dumps(manifest))
PY
"$BIN_DIR/VMProbe" "$ROOT_DIR/guest/artifacts" "$ROOT_DIR/evidence/local/vm" "$ROOT_DIR/.build-cache/guest-no-ready"
