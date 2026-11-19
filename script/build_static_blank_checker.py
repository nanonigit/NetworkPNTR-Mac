#!/usr/bin/env python3
"""Rebuild the isolated static checker experiment from the pinned Cloud Preview guest."""
import argparse
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

from build_local_session import ROOT, digest, docker, preflight
from local_session_packaging import verify

RECIPE = ROOT / 'guest/static-blank-checker'
PARENT_IMAGE = 'sha256:31c282753a7714f56fc3c0d98a76f69e1281f519f7edc6fbd137676a72441e3d'
PARENT_TAG = 'networkpntr-preserved-runtime:' + PARENT_IMAGE.removeprefix('sha256:')
CHECKER = '/rootfs/opt/artex-mac/check-blank-disk'
INIT = '/rootfs/sbin/artex-init'
OLD_CALL = b'python3 /opt/artex-mac/check_blank_disk.py || blank_status=$?'
NEW_CALL = b'/opt/artex-mac/check-blank-disk || blank_status=$?'
EXPECTED_CHECKER = '825c68880529552719bb1dffabc12d8fc587971c98c434018a5b8d9ffb3d01c3'
RECIPE_FILES = ('Dockerfile', 'check.c', 'test.c')


def inspect(image):
    entry, = json.loads(docker('image', 'inspect', image, timeout=15))
    if entry['Architecture'] != 'arm64' or entry['Os'] != 'linux':
        raise ValueError('Expected a local ARM64 Linux image')
    return entry['Id']


def read_file(image, path):
    return docker('run', '--rm', '--pull=never', '--network', 'none', '--read-only',
                  '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
                  '--entrypoint', 'cat', image, path, timeout=15)


def runtime_hashes(image):
    result = docker('run', '--rm', '--pull=never', '--network', 'none', '--read-only',
                    '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
                    '--entrypoint', 'sha256sum', image, '/system.ext4',
                    '/rootfs/opt/artex/artex', timeout=45)
    return [line.split()[0].decode() for line in result.splitlines()]


@contextmanager
def stopped_container(image):
    name = docker('create', '--network', 'none', image, timeout=20).decode().strip()
    try:
        yield name
    finally:
        docker('rm', name, timeout=30)


def build(control, output):
    if output.is_symlink():
        raise ValueError('Output cannot be a symlink')
    control, output = control.resolve(), output.resolve()
    parent = str(control).casefold() + '/'
    if output.exists() or str(output).casefold().startswith(parent):
        raise ValueError('Output must be a new directory outside the control artifacts')
    base = verify(control, output, 'cloud-preview')
    if base['guestRuntimeImage'] != PARENT_IMAGE:
        raise ValueError('Unexpected control runtime image')
    preflight()
    if inspect(PARENT_TAG) != PARENT_IMAGE:
        raise ValueError('Control image tag differs from the pinned runtime')
    if runtime_hashes(PARENT_IMAGE) != [base['systemDiskSHA256'], base['backendSHA256']]:
        raise ValueError('Control image differs from verified guest')
    init = read_file(PARENT_IMAGE, INIT)
    if init.count(OLD_CALL) != 1 or hashlib.sha256(init).hexdigest() != base['nativeSessionInitSHA256']:
        raise ValueError('Unexpected control init')
    control_manifest_hash = digest(control / 'manifest.json')

    with tempfile.TemporaryDirectory(prefix='static-checker-', dir=output.parent) as temp:
        staging = Path(temp)
        context = staging / 'context'
        context.mkdir()
        for name in RECIPE_FILES:
            shutil.copyfile(RECIPE / name, context / name)
        ref = staging / 'image.id'
        docker('buildx', 'build', '--builder', 'desktop-linux', '--load', '--platform', 'linux/arm64',
               '--pull=false', '--no-cache', '--network', 'none', '--iidfile', ref, context)
        image = ref.read_text().strip()
        if inspect(image) != image or inspect(PARENT_TAG) != PARENT_IMAGE:
            raise ValueError('Candidate or control image identity changed')
        checker_hash = hashlib.sha256(read_file(image, CHECKER)).hexdigest()
        candidate_init = read_file(image, INIT)
        if checker_hash != EXPECTED_CHECKER or candidate_init != init.replace(OLD_CALL, NEW_CALL):
            raise ValueError('Checker or init differs from the verified experiment')
        with stopped_container(image) as container:
            docker('cp', container + ':/system.ext4', staging / 'system.ext4', timeout=180)
        if (staging / 'system.ext4').stat().st_size != 768 * 1024 * 1024:
            raise ValueError('Unexpected candidate disk size')
        system_hash = digest(staging / 'system.ext4')
        if runtime_hashes(image) != [system_hash, base['backendSHA256']]:
            raise ValueError('Exported disk or retained backend differs from the candidate image')
        for key in ('kernel', 'initramfs'):
            name = base[key]
            shutil.copyfile(control / name, staging / name)
            if digest(staging / name) != base[key + 'SHA256']:
                raise ValueError('Control artifact changed while copying')
        manifest = dict(base, guestRuntimeImage=image, systemDiskSHA256=system_hash,
                        nativeSessionInitSHA256=hashlib.sha256(candidate_init).hexdigest())
        manifest['staticBlankCheckerExperiment'] = {
            'controlManifestSHA256': control_manifest_hash,
            'checkerSHA256': checker_hash,
            'buildInputsSHA256': {name: digest(context / name) for name in RECIPE_FILES},
            'deployment': 'diagnostic-only',
        }
        output.mkdir(mode=0o700)
        for name in ('Image', 'initramfs.cpio.gz', 'system.ext4'):
            (staging / name).rename(output / name)
        with (output / 'manifest.json').open('x') as receipt:
            receipt.write(json.dumps(manifest, indent=2) + '\n')
    return {'manifestSHA256': digest(output / 'manifest.json'), 'checkerSHA256': checker_hash}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--control', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.control, args.output)))


if __name__ == '__main__':
    main()
