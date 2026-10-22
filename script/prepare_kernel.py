#!/usr/bin/env python3
"""Compile a hash-pinned ARM64 guest kernel in an offline local Linux container."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
from urllib.parse import urlparse
import uuid

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ROOT / 'guest/kernel'
MAX_IMAGE = 256 * 1024 * 1024
REQUIRED_CONFIG = {
    'CONFIG_ARM64': 'y', 'CONFIG_ARM64_4K_PAGES': 'y', 'CONFIG_SMP': 'y',
    'CONFIG_MODULES': 'n', 'CONFIG_BLK_DEV_INITRD': 'n',
    'CONFIG_VIRTIO_BLK': 'y', 'CONFIG_VIRTIO_CONSOLE': 'y',
    'CONFIG_VIRTIO_VSOCKETS': 'y', 'CONFIG_VSOCKETS': 'y', 'CONFIG_HW_RANDOM_VIRTIO': 'y',
    'CONFIG_EXT4_FS': 'y', 'CONFIG_DEVTMPFS': 'y', 'CONFIG_DEVTMPFS_MOUNT': 'y',
    'CONFIG_UNIX': 'y', 'CONFIG_INET': 'y', 'CONFIG_PROC_FS': 'y', 'CONFIG_SYSFS': 'y',
    'CONFIG_HARDENED_USERCOPY': 'y', 'CONFIG_STACKPROTECTOR_STRONG': 'y',
    'CONFIG_RANDOMIZE_BASE': 'y', 'CONFIG_FORTIFY_SOURCE': 'y',
    'CONFIG_SECCOMP': 'y', 'CONFIG_SECCOMP_FILTER': 'y', 'CONFIG_DEBUG_INFO_NONE': 'y',
}


def bounded_digest(path: Path, maximum: int) -> str:
    try:
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= maximum:
            raise ValueError('Kernel input must be a bounded regular file')
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, 'rb') as handle:
            opened = os.fstat(handle.fileno())
            if not stat.S_ISREG(opened.st_mode) or not 0 < opened.st_size <= maximum:
                raise ValueError('Kernel input changed before opening')
            hasher = hashlib.sha256(); size = 0
            while block := handle.read(1024 * 1024):
                size += len(block)
                if size > maximum:
                    raise ValueError('Kernel input exceeds size limit')
                hasher.update(block)
            return hasher.hexdigest()
    except OSError as error:
        raise ValueError('Kernel build input is unavailable') from error


def sha256(path: Path) -> str:
    return bounded_digest(path, MAX_IMAGE)


def verified_file(path: Path, expected: str, maximum: int) -> Path:
    if bounded_digest(path, maximum) != expected:
        raise ValueError('Kernel input checksum mismatch: ' + path.name)
    return path


def load_lock() -> dict:
    lock = json.loads((INPUTS / 'source.lock.json').read_text())
    if not re.fullmatch(r'6\.12\.\d+', lock['version']):
        raise ValueError('Unexpected kernel source series')
    if not re.fullmatch(r'alpine:3\.22\.7@sha256:[0-9a-f]{64}', lock['builder_image']):
        raise ValueError('Builder base must be pinned by digest')
    for name in ['source', 'config', 'config_license']:
        value = lock[name]; parsed = urlparse(value['url'])
        if parsed.scheme != 'https' or parsed.hostname not in ['cdn.kernel.org', 'raw.githubusercontent.com'] or parsed.username or parsed.query or parsed.fragment:
            raise ValueError('Unexpected kernel input origin')
        if not re.fullmatch(r'[0-9a-f]{64}', value['sha256']) or not 0 < value['maximum_bytes'] <= MAX_IMAGE:
            raise ValueError('Invalid kernel input bounds or digest')
    for key, name in [('builder_packages_sha256', 'builder-packages.lock'), ('overrides_sha256', 'config-overrides')]:
        verified_file(INPUTS / name, lock[key], 1024 * 1024)
    if (INPUTS / 'Dockerfile').read_text().splitlines()[0] != 'FROM ' + lock['builder_image']:
        raise ValueError('Builder Dockerfile differs from its pinned base')
    if lock['jobs'] != 2 or lock['cpu_count'] != 1:
        raise ValueError('Unexpected experimental resource profile')
    return lock


def parse_config(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in text.splitlines():
        match = re.fullmatch(r'# (CONFIG_\w+) is not set', line)
        if match:
            key, value = match[1], 'n'
        elif re.fullmatch(r'CONFIG_\w+=.*', line):
            key, value = line.split('=', 1)
        else:
            continue
        if key in result:
            raise ValueError('Duplicate resolved kernel setting: ' + key)
        result[key] = value
    return result


def validate_config(values: dict[str, str]) -> None:
    for key, expected in REQUIRED_CONFIG.items():
        if values.get(key) != expected:
            raise ValueError('Required kernel setting differs: ' + key)


def validate_image(path: Path) -> None:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or not 64 <= info.st_size <= MAX_IMAGE:
        raise ValueError('Invalid kernel image file')
    with path.open('rb') as handle:
        if handle.read(64)[56:60] != b'ARM\x64':
            raise ValueError('Expected ARM64 Linux Image')


def require_new_output(path: Path) -> None:
    if path.exists() or path.is_symlink():
        raise ValueError('Output must be a new directory; existing artifacts are preserved')
    if not path.parent.is_dir() or path.parent.is_symlink():
        raise ValueError('Output parent must be an existing real directory')


def cached_input(item: dict) -> Path:
    cache = ROOT / '.build-cache/kernel-source'
    cache.mkdir(parents=True, exist_ok=True)
    if cache.is_symlink():
        raise ValueError('Kernel download cache must not be a symlink')
    name = Path(urlparse(item['url']).path).name
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', name):
        raise ValueError('Unexpected cache filename')
    target = cache / name
    if target.exists() or target.is_symlink():
        return verified_file(target, item['sha256'], item['maximum_bytes'])
    temporary = cache / (name + '.partial-' + uuid.uuid4().hex)
    try:
        subprocess.run(['curl', '--fail', '--location', '--proto', '=https', '--proto-redir', '=https',
                        '--connect-timeout', '10', '--max-time', '900', '--max-filesize', str(item['maximum_bytes']),
                        '--silent', '--show-error', item['url'], '--output', str(temporary)], check=True)
        verified_file(temporary, item['sha256'], item['maximum_bytes'])
        temporary.rename(target)
    finally:
        temporary.unlink(missing_ok=True)
    return target


def local_docker() -> list[str]:
    host = os.environ.get('DOCKER_HOST', '')
    if host and not host.startswith('unix://'):
        raise ValueError('Kernel build requires a local Unix-socket Docker context')
    context = subprocess.check_output(['docker', 'context', 'show'], text=True).strip()
    endpoint = subprocess.check_output(['docker', 'context', 'inspect', context, '--format', '{{.Endpoints.docker.Host}}'], text=True).strip()
    if not endpoint.startswith('unix://'):
        raise ValueError('Refusing a remote Docker build context')
    return ['docker', '--context', context]


def validate_builder_inspection(text: str, context: str) -> None:
    drivers = re.findall(r'^Driver:\s+(\S+)\s*$', text, re.MULTILINE)
    endpoints = re.findall(r'^Endpoint:\s+(\S+)\s*$', text, re.MULTILINE)
    if drivers != ['docker'] or endpoints != [context]:
        raise ValueError('Dependency image construction requires the selected local Docker driver')


def retain_pinned_inputs(context: Path, target: Path, lock: dict) -> None:
    for key, name in [('source', 'linux-source.tar.xz'), ('config_license', 'config-LICENSE')]:
        item = lock[key]
        verified_file(context / name, item['sha256'], item['maximum_bytes'])
        shutil.copyfile(context / name, target / name)
        verified_file(target / name, item['sha256'], item['maximum_bytes'])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'guest/source-kernel-artifacts')
    args = parser.parse_args(); output = args.output.absolute()
    require_new_output(output)
    if shutil.disk_usage(ROOT).free < 12 * 1024 ** 3:
        raise ValueError('At least 12 GiB of free space is required before this bounded experiment')
    lock = load_lock()
    sources = {name: cached_input(lock[name]) for name in ['source', 'config', 'config_license']}
    docker = local_docker()
    builder = docker[-1]
    inspection = subprocess.check_output(docker + ['buildx', 'inspect', builder], text=True)
    validate_builder_inspection(inspection, builder)
    container = None
    with tempfile.TemporaryDirectory(prefix='kernel-context-', dir=ROOT / '.build-cache') as directory:
        context = Path(directory)
        for source, name in [(sources['source'], 'linux-source.tar.xz'), (sources['config'], 'base.config'),
                             (sources['config_license'], 'config-LICENSE'), (Path(__file__), 'prepare_kernel.py')]:
            shutil.copyfile(source, context / name)
        for name in ['Dockerfile', 'build-kernel.sh', 'config-overrides', 'builder-packages.lock', 'source.lock.json']:
            shutil.copyfile(INPUTS / name, context / name)
        recipe = hashlib.sha256()
        for path in sorted(context.iterdir()):
            recipe.update(path.name.encode() + b'\0'); recipe.update(bytes.fromhex(sha256(path)))
        recipe_hash = recipe.hexdigest()
        image = 'artex-mac-kernel-builder:' + recipe_hash[:16]
        subprocess.run(docker + ['buildx', 'build', '--builder', builder, '--load', '--platform', 'linux/arm64', '--tag', image, str(context)], check=True)
        inspected = json.loads(subprocess.check_output(docker + ['image', 'inspect', image]))[0]
        if inspected['Architecture'] != 'arm64':
            raise ValueError('Kernel builder architecture mismatch')
        try:
            container = subprocess.check_output(docker + ['create', '--name', 'artex-mac-kernel-' + uuid.uuid4().hex[:12],
                '--network', 'none', '--cpus', '2', '--memory', '3g', '--pids-limit', '512', '--cap-drop', 'ALL',
                '--security-opt', 'no-new-privileges:true', image], text=True).strip()
            config = json.loads(subprocess.check_output(docker + ['inspect', container]))[0]
            if config['HostConfig']['NetworkMode'] != 'none' or config['Mounts'] or config['HostConfig']['Privileged']:
                raise ValueError('Kernel compilation isolation differs')
            subprocess.run(docker + ['start', '--attach', container], check=True)
            state = json.loads(subprocess.check_output(docker + ['inspect', container]))[0]['State']
            if state['ExitCode'] != 0 or state['OOMKilled']:
                raise ValueError('Kernel build failed or exceeded memory budget')
            with tempfile.TemporaryDirectory(prefix='kernel-output-', dir=output.parent) as staging:
                target = Path(staging)
                for name in ['Image', 'kernel.config', 'build-report.json', 'COPYING', 'LICENSES.tar.gz']:
                    subprocess.run(docker + ['cp', container + ':/out/' + name, str(target / name)], check=True)
                    path = target / name
                    verified_file(path, sha256(path), MAX_IMAGE)
                report = json.loads((target / 'build-report.json').read_text())
                if report['timestamp'] != lock['build_timestamp'] or report['compileJobs'] != lock['jobs'] or report['packageLockSHA256'] != lock['builder_packages_sha256']:
                    raise ValueError('Kernel build environment report differs')
                if report['kernelSHA256'] != sha256(target / 'Image') or report['configSHA256'] != sha256(target / 'kernel.config'):
                    raise ValueError('Kernel build report hashes differ')
                validate_image(target / 'Image')
                validate_config(parse_config((target / 'kernel.config').read_text()))
                retain_pinned_inputs(context, target, lock)
                manifest = {'version': lock['version'], 'source': lock['source'], 'configSource': lock['config'],
                            'configSourceCommit': lock['config_source_commit'], 'recipeSHA256': recipe_hash,
                            'builderImage': inspected['Id'], 'builderBase': lock['builder_image'],
                            'networkMode': 'none', 'hostShares': 0, 'cpuCount': 1,
                            'files': {path.name: sha256(path) for path in sorted(target.iterdir())}}
                (target / 'kernel-build.json').write_text(json.dumps(manifest, indent=2) + '\n')
                require_new_output(output)
                target.rename(output)
        finally:
            if container:
                subprocess.run(docker + ['rm', '--force', container], check=False, stdout=subprocess.DEVNULL)
    print('Source kernel built offline in a private Linux container: ' + str(output))


if __name__ == '__main__':
    main()
