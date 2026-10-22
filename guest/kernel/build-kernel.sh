#!/bin/sh
set -eu
umask 022
export LC_ALL=C TZ=UTC ARCH=arm64
[ "$(uname -m)" = aarch64 ] || { echo 'Expected Linux ARM64 builder' >&2; exit 1; }
mkdir -p /build /out
# This entry point runs only in a private container with network=none and no mounts.
python3 - <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, '/tools')
from prepare_kernel import verified_file
lock = json.loads(Path('/inputs/source.lock.json').read_text())
for key, name in [('source', 'linux-source.tar.xz'), ('config', 'base.config'), ('config_license', 'config-LICENSE')]:
    item = lock[key]
    verified_file(Path('/inputs') / name, item['sha256'], item['maximum_bytes'])
PY
tar -xJf /inputs/linux-source.tar.xz -C /build
mv /build/linux-* /build/linux
cd /build/linux
scripts/kconfig/merge_config.sh -m /inputs/base.config /inputs/config-overrides
export KBUILD_BUILD_TIMESTAMP='2026-10-22T00:00:00Z'
export KBUILD_BUILD_USER=artex KBUILD_BUILD_HOST=isolated-builder KBUILD_BUILD_VERSION=1
make olddefconfig
python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0, '/tools')
from prepare_kernel import parse_config, validate_config
validate_config(parse_config(Path('.config').read_text()))
PY
make -j2 Image
cp arch/arm64/boot/Image /out/Image
cp .config /out/kernel.config
cp COPYING /out/COPYING
tar -czf /out/LICENSES.tar.gz LICENSES
python3 - <<'PY'
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, '/tools')
from prepare_kernel import sha256, validate_image
validate_image(Path('/out/Image'))
report = {'kernelRelease': subprocess.check_output(['make', '-s', 'kernelrelease'], text=True).strip(),
          'compiler': subprocess.check_output(['gcc', '--version'], text=True).splitlines()[0],
          'packageLockSHA256': sha256(Path('/actual-packages.lock')), 'configSHA256': sha256(Path('.config')),
          'kernelSHA256': sha256(Path('/out/Image')), 'timestamp': '2026-10-22T00:00:00Z',
          'compileJobs': 2}
Path('/out/build-report.json').write_text(json.dumps(report, indent=2) + '\n')
PY
