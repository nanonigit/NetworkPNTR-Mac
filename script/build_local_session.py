#!/usr/bin/env python3
"""Build reviewed native-session Linux backends and overlay a verified guest variant."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
import uuid
from local_session_bootstrap import patch_init

ROOT = Path(__file__).resolve().parents[1]
COMMIT = 'e75ae371ad777ffd1eecdd28d2781a6519b05591'
BUILDER = 'golang:1.26.3-bookworm@sha256:386d475a660466863d9f8c766fec64d7fdad3edac2c6a05020c09534d71edb4b'
ENV = {k: v for k, v in os.environ.items() if not k.startswith(('DOCKER_', 'BUILDKIT_'))}
DOCKER = ['/usr/local/bin/docker', '--context', 'desktop-linux']


def docker(*args, timeout=1800):
    return subprocess.check_output([*DOCKER, *map(str, args)], env=ENV, timeout=timeout)


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def preflight():
    expected = 'unix://' + str(Path.home() / '.docker/run/docker.sock')
    endpoint = docker('context', 'inspect', 'desktop-linux', '--format', '{{.Endpoints.docker.Host}}', timeout=10).decode().strip()
    if endpoint != expected or not Path(endpoint[7:]).is_socket():
        raise ValueError('Expected local Docker Desktop Unix socket')
    from evidence_reference_host import builder_is_local
    if not builder_is_local(docker('buildx', 'inspect', 'desktop-linux', timeout=15).decode()):
        raise ValueError('Expected local builder')
    inspection = json.loads(docker('image', 'inspect', BUILDER, timeout=10))[0]
    if inspection['Architecture'] != 'arm64':
        raise ValueError('Expected cached arm64 builder')


def export_source(repository, destination):
    raw = subprocess.check_output(['git', '-C', str(repository), 'archive', COMMIT], timeout=60)
    destination.mkdir()
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        for member in archive:
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or not (member.isdir() or member.isfile()):
                raise ValueError('Unsafe source archive entry')
            target = destination.joinpath(*name.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with target.open('xb') as stream:
                    shutil.copyfileobj(archive.extractfile(member), stream)
                target.chmod(member.mode & 0o777)


def build_backend(repository, profile, context):
    export_source(repository, context / 'source')
    native = ROOT / 'guest/native-session'
    if profile == 'cloud':
        extension = ROOT / 'guest/backend-extension'
        for source, target in [('agent', 'agent-extension'), ('server', 'server-extension'),
                               ('traffic', 'traffic-extension'), ('cloud-origin', 'origin-extension')]:
            shutil.copytree(extension / source, context / target)
        for patch in extension.glob('*.patch'):
            shutil.copyfile(patch, context / patch.name)
        recipe = (extension / 'Dockerfile.provider-tests').read_text()
        start = recipe.index('SHELL [')
        recipe = recipe[:start] + '''COPY native-server/ ./server/
COPY native.patch /tmp/native.patch
RUN --network=none git apply --check /tmp/native.patch && git apply /tmp/native.patch
RUN --network=none GOMAXPROCS=2 go test -p 2 -mod=readonly github.com/Autumn-27/norma/llm github.com/Autumn-27/norma/harness ./traffic ./agent ./server ./db ./cloudegress -count=1
RUN --network=none GOMAXPROCS=2 go build -p 2 -mod=readonly -trimpath -buildvcs=false -ldflags="-s -w" -o /out/backend ./cmd/artex
'''
        shutil.copytree(native / 'server', context / 'native-server')
        shutil.copyfile(native / 'managed.patch', context / 'native.patch')
    else:
        recipe = (native / 'Dockerfile').read_text()
        shutil.copytree(native / 'server', context / 'server')
        shutil.copyfile(native / 'managed.patch', context / 'managed.patch')
    (context / 'Dockerfile').write_text(recipe)
    docker('buildx', 'build', '--builder', 'desktop-linux', '--load', '--platform', 'linux/arm64',
           '--pull=false', '--iidfile', context / 'image.id', context)
    return (context / 'image.id').read_text().strip()


def overlay(artifacts, output, backend_image, context):
    original = json.loads((artifacts / 'manifest.json').read_text())
    for key in ('kernel', 'initramfs', 'systemDisk'):
        name = original[key]
        if not isinstance(name, str) or not name or Path(name).name != name or '\\' in name:
            raise ValueError('Unsafe artifact name')
        if digest(artifacts / name) != original[key + 'SHA256']:
            raise ValueError('Input artifact integrity mismatch')
    runtime = original['guestRuntimeImage']
    if not isinstance(runtime, str) or len(runtime) != 71 or not runtime.startswith('sha256:'):
        raise ValueError('Pinned runtime required')
    inspection = json.loads(docker('image', 'inspect', runtime))[0]
    if inspection['Id'] != runtime or inspection['Architecture'] != 'arm64':
        raise ValueError('Runtime identity mismatch')
    def read(image, path):
        return docker('run', '--rm', '--pull=never', '--network', 'none', '--read-only',
                      '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true', '--entrypoint', 'cat', image, path)
    hashes = docker('run', '--rm', '--pull=never', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
                    '--security-opt', 'no-new-privileges:true', '--entrypoint', 'sha256sum', runtime,
                    '/system.ext4', '/rootfs/opt/artex/artex').decode().splitlines()
    if [line.split()[0] for line in hashes] != [original['systemDiskSHA256'], original['backendSHA256']]:
        raise ValueError('Runtime differs from supplied artifacts')
    init = patch_init(read(runtime, '/rootfs/sbin/artex-init'))
    (context / 'backend-init').write_bytes(init)
    (context / 'backend').write_bytes(read(backend_image, '/out/backend'))
    original_tags = list(inspection.get('RepoTags') or [])
    if not original_tags:
        # Keep a durable content-addressed pin: deleting the only temporary alias
        # of a formerly dangling image would otherwise delete the input itself.
        retained = 'networkpntr-preserved-runtime:' + runtime.removeprefix('sha256:')
        existing = subprocess.run([*DOCKER, 'image', 'inspect', retained], env=ENV,
                                  capture_output=True, timeout=10)
        if existing.returncode == 0 and json.loads(existing.stdout)[0]['Id'] != runtime:
            raise ValueError('Preserved runtime tag collision')
        docker('tag', runtime, retained)
        original_tags = [retained]
    parent = 'networkpntr-local-parent:' + uuid.uuid4().hex
    docker('tag', runtime, parent)
    try:
        recipe = f'''FROM {parent}
COPY backend /rootfs/opt/artex/artex
COPY backend-init /rootfs/sbin/artex-init
RUN --network=none echo '{digest(context / 'backend')}  /rootfs/opt/artex/artex' | sha256sum -c - \\
    && echo '{digest(context / 'backend-init')}  /rootfs/sbin/artex-init' | sha256sum -c - \\
    && chmod 755 /rootfs/opt/artex/artex /rootfs/sbin/artex-init \\
    && unlink /system.ext4 && truncate -s 768M /system.ext4 \\
    && mkfs.ext4 -q -F -L artex-system -O ^has_journal -d /rootfs /system.ext4
'''
        (context / 'Dockerfile').write_text(recipe)
        docker('buildx', 'build', '--builder', 'desktop-linux', '--load', '--platform', 'linux/arm64',
               '--pull=false', '--network', 'none', '--iidfile', context / 'runtime.id', context)
        image = (context / 'runtime.id').read_text().strip()
        if docker('image', 'inspect', parent, '--format', '{{.Id}}').decode().strip() != runtime:
            raise ValueError('Runtime parent changed')
        output.mkdir(mode=0o700)
        container = docker('create', '--network', 'none', image).decode().strip()
        copy_error = None
        try:
            docker('cp', container + ':/system.ext4', output / original['systemDisk'])
        except Exception as error:
            copy_error = error
            raise
        finally:
            try:
                docker('rm', container, timeout=30)
            except Exception as cleanup_error:
                if copy_error is not None:
                    raise ExceptionGroup('Guest extraction and cleanup failed', [copy_error, cleanup_error])
                raise
        for key in ('kernel', 'initramfs'):
            shutil.copyfile(artifacts / original[key], output / original[key])
        manifest = dict(original)
        manifest.update(systemDiskSHA256=digest(output / original['systemDisk']), backendSHA256=digest(context / 'backend'),
                        guestRuntimeImage=image, nativeSessionParentImage=runtime,
                        nativeSessionParentManifestSHA256=digest(artifacts / 'manifest.json'),
                        nativeSessionRecipeSHA256=hashlib.sha256(recipe.encode()).hexdigest(),
                        nativeSessionInitSHA256=digest(context / 'backend-init'),
                        nativeSessionBackendBuildImage=backend_image,
                        managedCapabilities=sorted(set(original.get('managedCapabilities') or []) | {'native-local-session-v1'}))
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    finally:
        remove_owned_parent_alias(runtime, parent, original_tags)

def remove_owned_parent_alias(runtime, parent, original_tags):
    # Delete only the owned alias, with parent pruning disabled, after proving
    # that a durable input reference still exists. Retain it on mismatch.
    if not original_tags:
        raise ValueError('Durable input reference required; temporary alias retained')
    current = json.loads(docker('image', 'inspect', runtime, timeout=10))[0]
    if not set(original_tags).issubset(set(current.get('RepoTags') or [])):
        raise ValueError('Input references changed; temporary alias retained')
    for tag in original_tags:
        if docker('image', 'inspect', tag, '--format', '{{.Id}}', timeout=10).decode().strip() != runtime:
            raise ValueError('Input tag changed; temporary alias retained')
    if docker('image', 'inspect', parent, '--format', '{{.Id}}', timeout=10).decode().strip() != runtime:
        raise ValueError('Temporary alias changed; retained for inspection')
    docker('image', 'rm', '--no-prune', parent, timeout=30)



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--profile', required=True, choices=['default', 'cloud'])
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output must be a new directory')
    preflight()
    # Keep private build evidence on failure; no credentials or VM state are placed here.
    context = Path(tempfile.mkdtemp(prefix='native-session-', dir=ROOT / '.build-cache'))
    backend = build_backend(args.source.resolve(), args.profile, context)
    overlay_context = context / 'overlay'
    overlay_context.mkdir()
    overlay(args.artifacts.resolve(), args.output.resolve(), backend, overlay_context)
    print(json.dumps({'profile': args.profile, 'manifestSHA256': digest(args.output / 'manifest.json')}))


if __name__ == '__main__':
    main()
