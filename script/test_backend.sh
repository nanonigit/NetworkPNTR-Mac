#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$#" -ne 1 ]; then
    echo 'Usage: script/test_backend.sh /path/to/clean/pinned/artex-global'
    exit 2
fi
SOURCE_DIR="$(cd "$1" && pwd)"
cd "$ROOT_DIR"
python3 script/prepare_backend.py --source "$SOURCE_DIR"
swift build --product VMProbe
BIN_DIR="$(swift build --show-bin-path)"
codesign --force --sign - --entitlements guest/entitlements.plist "$BIN_DIR/VMProbe"
mkdir -p evidence/backend evidence/local/backend
"$BIN_DIR/VMProbe" --backend "$ROOT_DIR/guest/backend-artifacts" "$ROOT_DIR/evidence/local/backend" | tee evidence/backend/vm-summary.txt
cp evidence/local/backend/api-contract-vm.json evidence/backend/api-contract-vm.json
python3 script/compare_backend.py evidence/backend/api-contract-vm.json evidence/backend
