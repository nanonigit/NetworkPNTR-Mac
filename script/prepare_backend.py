#!/usr/bin/env python3
"""Build Linux guest artifacts inside Docker; Docker is never an app runtime dependency."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import tarfile
import prepare_guest

ROOT = Path(__file__).resolve().parents[1]
SOURCE_COMMIT = 'e75ae371ad777ffd1eecdd28d2781a6519b05591'
BACKEND_IMAGE = 'sha256:46b3ce5d5f91cd05b9e3fd6834e33196be9626eb40d38e84b7fb398f00a172d0'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def digest(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def module_initramfs(linux, busybox):
    files = {'bin/busybox': (stat.S_IFREG | 0o755, prepare_guest.member(busybox, 'bin/busybox.static')),
             'bin/sh': (stat.S_IFLNK | 0o777, b'busybox'),
             'sbin/modprobe': (stat.S_IFLNK | 0o777, b'../bin/busybox'),
             'init': (stat.S_IFREG | 0o755, (ROOT / 'guest/backend-early-init').read_bytes())}
    with tarfile.open(linux, 'r:gz', ignore_zeros=True) as archive:
        for info in archive:
            name = PurePosixPath(info.name)
            if not str(name).startswith('lib/modules/'):
                continue
            if name.is_absolute() or '..' in name.parts:
                raise ValueError('Unsafe module archive path')
            if info.isfile() and info.size <= 32 * 1024 * 1024:
                files[str(name)] = (stat.S_IFREG | 0o644, archive.extractfile(info).read())
    directories = {'.', 'bin', 'dev', 'proc', 'sys', 'run', 'newroot', 'tmp'}
    for name in files:
        directories.update(str(parent) for parent in PurePosixPath(name).parents)
    archive = b''.join(prepare_guest.entry(name, stat.S_IFDIR | 0o755, inode=index + 1)
                       for index, name in enumerate(sorted(directories)))
    archive += prepare_guest.entry('dev/console', stat.S_IFCHR | 0o600, inode=10000, rdevmajor=5, rdevminor=1)
    for index, (name, (mode, content)) in enumerate(sorted(files.items())):
        archive += prepare_guest.entry(name, mode, content, inode=10001 + index)
    archive += prepare_guest.entry('TRAILER!!!', 0, inode=20000)
    return gzip.compress(archive, mtime=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path, help='Clean checkout of the pinned browser source')
    args = parser.parse_args()
    head = subprocess.check_output(['git', '-C', str(args.source), 'rev-parse', 'HEAD'], text=True).strip()
    dirty = subprocess.check_output(['git', '-C', str(args.source), 'status', '--porcelain'], text=True).strip()
    if head != SOURCE_COMMIT or dirty:
        raise SystemExit('Expected the clean pinned browser source; refusing a different build input')
    inspection = json.loads(subprocess.check_output(['docker', 'image', 'inspect', BACKEND_IMAGE]))[0]
    if inspection['Architecture'] != 'arm64' or inspection['Config']['Labels'].get('org.opencontainers.image.revision') != SOURCE_COMMIT:
        raise SystemExit('Backend image provenance mismatch; rebuild the pinned browser deployment first')
    context = ROOT / '.build-cache/backend-context'
    context.mkdir(parents=True, exist_ok=True)
    identifier = subprocess.check_output(['docker', 'create', BACKEND_IMAGE], text=True).strip()
    try:
        run('docker', 'cp', identifier + ':/opt/artex/artex', str(context / 'artex'))
        shutil.rmtree(context / 'skills', ignore_errors=True)
        run('docker', 'cp', identifier + ':/opt/artex/skills', str(context / 'skills'))
    finally:
        run('docker', 'rm', identifier, stdout=subprocess.DEVNULL)
    for name in ['backend.Dockerfile', 'backend-init', 'vsock_relay.py', 'check_blank_disk.py', 'backend-packages.lock']:
        shutil.copyfile(ROOT / 'guest' / name, context / name)
    run('docker', 'build', '--platform', 'linux/arm64', '-f', str(context / 'backend.Dockerfile'), '-t', 'artex-mac-guest:phase2', str(context))
    output = ROOT / 'guest/backend-artifacts'
    output.mkdir(parents=True, exist_ok=True)
    identifier = subprocess.check_output(['docker', 'create', 'artex-mac-guest:phase2'], text=True).strip()
    try:
        run('docker', 'cp', identifier + ':/system.ext4', str(output / 'system.ext4'))
        run('docker', 'cp', identifier + ':/rootfs/opt/artex-mac/packages.lock', str(output / 'packages.lock'))
    finally:
        run('docker', 'rm', identifier, stdout=subprocess.DEVNULL)
    linux, _ = prepare_guest.package('linux-virt')
    busybox, _ = prepare_guest.package('busybox-static')
    (output / 'Image').write_bytes(prepare_guest.unpack_kernel(prepare_guest.member(linux, 'boot/vmlinuz-virt')))
    (output / 'initramfs.cpio.gz').write_bytes(module_initramfs(linux, busybox))
    manifest = {'architecture': 'arm64', 'kernel': 'Image', 'initramfs': 'initramfs.cpio.gz', 'systemDisk': 'system.ext4',
                'sourceCommit': SOURCE_COMMIT, 'backendImage': BACKEND_IMAGE,
                'backendSHA256': digest(context / 'artex'), 'packageLockSHA256': digest(output / 'packages.lock'),
                'networkDevices': 0, 'hostShares': 0}
    for key in ['kernel', 'initramfs', 'systemDisk']:
        manifest[key + 'SHA256'] = digest(output / manifest[key])
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Backend guest artifacts built; Linux executables ran only inside the build container.')


if __name__ == '__main__':
    main()
