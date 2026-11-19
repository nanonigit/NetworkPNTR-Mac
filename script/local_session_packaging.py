"""Validate native-session guest inputs before a generated bundle is replaced."""
import hashlib
import json
from pathlib import Path
import re
import sys

PINNED_SOURCE = 'e75ae371ad777ffd1eecdd28d2781a6519b05591'


def verify(guest, bundle, variant="default"):
    guest, bundle = Path(guest).resolve(), Path(bundle).resolve()
    # macOS commonly uses case-insensitive filesystems. Deny aliases as well as
    # symlinks into the destination that packaging will remove.
    source, destination = str(guest).casefold(), str(bundle).casefold()
    if source == destination or source.startswith(destination + '/'):
        raise ValueError('Guest input must be outside the bundle being replaced')
    path = guest / 'manifest.json'
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 65536:
        raise ValueError('Expected bounded regular guest manifest')
    manifest = json.loads(path.read_text())
    capabilities = manifest.get('managedCapabilities')
    if not isinstance(capabilities, list) or not all(isinstance(value, str) for value in capabilities):
        raise ValueError('Expected a typed native capability array')
    if manifest.get('sourceCommit') != PINNED_SOURCE or 'native-local-session-v1' not in capabilities:
        raise ValueError('Rebuild the pinned guest with native-local-session-v1 before packaging')
    cloud = 'cloud-vsock-fixture-v1' in capabilities
    if variant not in {'default', 'cloud-preview'} or cloud != (variant == 'cloud-preview'):
        raise ValueError('Guest does not match the selected application variant')
    if cloud:
        reference = Path(__file__).resolve().parents[1] / 'evidence/local-session/cloud-composite-manifest.json'
        if path.read_bytes() != reference.read_bytes():
            raise ValueError('Cloud guest must match the reviewed composite manifest')
    filenames = {'kernel': 'Image', 'initramfs': 'initramfs.cpio.gz', 'systemDisk': 'system.ext4'}
    for key in filenames:
        name, expected = manifest.get(key), manifest.get(key + 'SHA256')
        if name != filenames[key]:
            raise ValueError('Invalid guest filename')
        if not isinstance(expected, str) or re.fullmatch('[0-9a-f]{64}', expected) is None:
            raise ValueError('Invalid guest digest')
        artifact = guest / name
        if artifact.is_symlink() or not artifact.is_file() or not 0 < artifact.stat().st_size <= 1024 * 1024 * 1024:
            raise ValueError('Expected bounded regular guest artifact')
        with artifact.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:
                raise ValueError('Guest artifact integrity mismatch')
    return manifest


if __name__ == '__main__':
    if len(sys.argv) not in (3, 4):
        raise SystemExit('Usage: local_session_packaging.py GUEST_DIRECTORY DESTINATION_APP [default|cloud-preview]')
    verify(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] if len(sys.argv) == 4 else "default")
