# Managed backend extensions

Base source: e75ae371ad777ffd1eecdd28d2781a6519b05591. The frozen browser checkout is never edited. This overlay adds an authenticated structured original-blob metadata handler and patches managed Traffic.Blob to use the hardened opener, with legacy hash normalization preserved. It is test-compiled, not a deployed VM guest or native save feature. See docs/traffic-blob-design.md for the remaining handler/auth/stream/build/native/UI/runtime gates.

The pinned Linux/arm64 Go builder verifies go.mod/go.sum dependencies, checks/applies managed.patch, runs the complete traffic/server package tests with network disabled and builds /out/artex as a CGO-free Linux/arm64 backend without embedded browser UI. Existing database/fixture-dependent skipped tests remain explicitly unverified. Host Python only stages a safe Git archive and orchestrates Docker; it does not run the application or Go compiler. From the ARTEX Mac repository root:

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
    shutil.copy2(root / 'guest/backend-extension/managed.patch', context / 'managed.patch')
    subprocess.run(['docker', 'build', '--progress=plain', '-f', str(root / 'guest/backend-extension/Dockerfile.tests'), str(context)], check=True)
PY
```

No new dependency is added. Ordinary and legacy blob layouts use descriptor-relative nonblocking/no-follow opens and regular-file checks. The frozen checkout is unchanged; only its managed copy of Blob uses the hardened opener. The metadata route remains inside the existing JWT middleware and distinguishes400/404/503 without exposing raw SQL errors. Do not infer original-blob ownership from raw HTTP marker text or manufacture findings/bindings for export. No host share, Docker socket mount, existing state mount, external scan, cloud call or runtime profile promotion is part of this recipe.
