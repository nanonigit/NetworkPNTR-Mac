#!/usr/bin/env python3
"""Combine verified source-kernel and backend inputs without replacing either profile."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import tempfile
from prepare_kernel import load_lock, parse_config, require_new_output, validate_config, validate_image, verified_file

SOURCE_COMMIT = 'e75ae371ad777ffd1eecdd28d2781a6519b05591'
ALLOWED_KERNEL_FILES = {'Image', 'kernel.config', 'build-report.json', 'COPYING', 'LICENSES.tar.gz', 'linux-source.tar.xz', 'config-LICENSE'}


def leaf(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_.-]+', value) or value in ['.', '..']:
        raise ValueError('Artifact paths must be safe leaf filenames')
    return value


def read_manifest(path: Path) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 64 * 1024:
        raise ValueError('Invalid artifact manifest file')
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError('Artifact manifest must be an object')
    return value


def assemble(backend: Path, kernel: Path, output: Path) -> None:
    require_new_output(output)
    if backend.is_symlink() or kernel.is_symlink():
        raise ValueError('Input artifact directories must not be symlinks')
    original = read_manifest(backend / 'manifest.json')
    build = read_manifest(kernel / 'kernel-build.json')
    lock = load_lock()
    if original.get('architecture') != 'arm64' or original.get('sourceCommit') != SOURCE_COMMIT:
        raise ValueError('Backend must use the pinned ARM64 source')
    if original.get('networkDevices') != 0 or original.get('hostShares') != 0:
        raise ValueError('Backend isolation provenance differs')
    if build.get('version') != lock['version'] or build.get('source') != lock['source'] or build.get('configSource') != lock['config']:
        raise ValueError('Kernel source provenance differs from the source lock')
    if build.get('networkMode') != 'none' or build.get('hostShares') != 0:
        raise ValueError('Kernel compilation isolation provenance differs')
    files = build.get('files')
    if not isinstance(files, dict) or set(files) != ALLOWED_KERNEL_FILES:
        raise ValueError('Unexpected kernel artifact file inventory')
    for name, digest in files.items():
        verified_file(kernel / leaf(name), digest, 256 * 1024 * 1024)
    for key, name in [('source', 'linux-source.tar.xz'), ('config_license', 'config-LICENSE')]:
        item = lock[key]
        verified_file(kernel / name, item['sha256'], item['maximum_bytes'])
    report = read_manifest(kernel / 'build-report.json')
    if report.get('kernelSHA256') != files['Image'] or report.get('configSHA256') != files['kernel.config'] or report.get('packageLockSHA256') != lock['builder_packages_sha256']:
        raise ValueError('Kernel build report differs from its artifact inventory')
    validate_image(kernel / 'Image')
    validate_config(parse_config((kernel / 'kernel.config').read_text()))
    inputs: dict[str, tuple[Path, str, int]] = {'Image': (kernel / 'Image', files['Image'], 256 * 1024 * 1024)}
    for key, maximum in [('systemDisk', 1024 * 1024 * 1024), ('initramfs', 256 * 1024 * 1024)]:
        name = leaf(original[key]); digest = original[key + 'SHA256']
        verified_file(backend / name, digest, maximum)
        if name in inputs:
            raise ValueError('Kernel and backend artifact filenames must be distinct')
        inputs[name] = (backend / name, digest, maximum)
    with tempfile.TemporaryDirectory(prefix='source-profile-', dir=output.parent) as staging:
        target = Path(staging)
        for name, (path, digest, maximum) in inputs.items():
            shutil.copyfile(path, target / name)
            verified_file(target / name, digest, maximum)
        provenance = target / 'Provenance'; provenance.mkdir()
        for name, digest in files.items():
            if name == 'Image':
                continue
            shutil.copyfile(kernel / name, provenance / name)
            verified_file(provenance / name, digest, 256 * 1024 * 1024)
        (provenance / 'kernel-build.json').write_text(json.dumps(build, indent=2) + '\n')
        manifest = dict(original)
        manifest.update({'kernel': 'Image', 'kernelSHA256': files['Image'], 'bootMode': 'rootDisk', 'cpuCount': 1,
                         'kernelPackage': {'source': lock['source'], 'configuration': lock['config'], 'recipeSHA256': build['recipeSHA256']}})
        (target / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        require_new_output(output)
        target.rename(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', required=True, type=Path)
    parser.add_argument('--kernel', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    assemble(args.backend, args.kernel, args.output)
    print('Verified source-kernel backend candidate assembled: ' + str(args.output))


if __name__ == '__main__':
    main()
