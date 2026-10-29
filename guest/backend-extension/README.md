# Managed backend extensions

Base source: e75ae371ad777ffd1eecdd28d2781a6519b05591. The frozen browser checkout is never edited. This overlay currently adds only the stored original-blob metadata primitive and its tests. It is not a deployed API, guest image or native save feature. See docs/traffic-blob-design.md for the remaining handler/auth/stream/build/native/UI/runtime gates.

The pinned Linux/arm64 Go builder verifies go.mod/go.sum dependencies, then runs the complete traffic package tests with network disabled. Host Python only stages a safe Git archive and orchestrates Docker; it does not run the application or Go compiler. From the ARTEX Mac repository root:

```sh
python3 - <<'PY'
from pathlib import Path
import io, shutil, subprocess, tarfile, tempfile
root = Path.cwd()
with tempfile.TemporaryDirectory(prefix='artex-managed-blob-') as temp:
    context = Path(temp)
    source = context / 'source'
    source.mkdir()
    archive = subprocess.check_output(['git', '-C', str(root / '../artex-local/source'), 'archive', 'e75ae371ad777ffd1eecdd28d2781a6519b05591'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        tree.extractall(source, filter='data')
    shutil.copytree(root / 'guest/backend-extension/traffic', context / 'extension')
    shutil.copytree(root / 'guest/backend-extension/server', context / 'server-extension')
    subprocess.run(['docker', 'build', '--progress=plain', '-f', str(root / 'guest/backend-extension/Dockerfile.tests'), str(context)], check=True)
PY
```

No new dependency is added. Ordinary and legacy blob layouts use descriptor-relative nonblocking/no-follow opens and regular-file checks. The inherited frozen Blob streaming method is unchanged; the future managed download path must use the hardened opener too before deployment. Do not infer original-blob ownership from raw HTTP marker text or manufacture findings/bindings for export. No host share, Docker socket mount, existing state mount, external scan, cloud call or runtime profile promotion is part of this recipe.
