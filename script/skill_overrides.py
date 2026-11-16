"""Bundle reviewed local skill content into a verified guest image."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid
from captured_reference_host import DOCKER, local_context
from evidence_reference_host import builder_is_local

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / 'guest/skill-overrides/api-recon/SKILL.md'
RELATIVE = 'api-recon/SKILL.md'


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def declaration():
    return {'api-recon': {'file': RELATIVE, 'sha256': digest(SKILL)}}


def apply_to_context(skills):
    destination = Path(skills) / RELATIVE
    if not destination.resolve().is_relative_to(Path(skills).resolve()):
        raise ValueError('Skill override destination escapes the build context')
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SKILL, destination)


def verify_manifest(path):
    manifest = json.loads(Path(path).read_text())
    if manifest.get('skillOverrides') != declaration():
        raise ValueError('Guest skill overrides are stale; rebuild before packaging')
    return manifest


def docker(*args, capture=False):
    result = subprocess.run([*DOCKER, *map(str, args)], check=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.decode().strip() if capture else None


def require_local_builder():
    endpoint = docker('context', 'inspect', 'desktop-linux', '--format', '{{.Endpoints.docker.Host}}', capture=True)
    if not local_context(endpoint) or not Path(endpoint[7:]).is_socket():
        raise ValueError('A local Unix Docker endpoint is required')
    if not builder_is_local(docker('buildx', 'inspect', 'desktop-linux', capture=True)):
        raise ValueError('The named local Docker builder is required')


def build(artifacts, output, runtime):
    require_local_builder()
    artifacts = artifacts.resolve()
    original = json.loads((artifacts / 'manifest.json').read_text())
    for key in ('kernel', 'initramfs', 'systemDisk'):
        name = original[key]
        if not isinstance(name, str) or not name or Path(name).name != name or '\\' in name:
            raise ValueError('Invalid guest artifact filename')
        if digest(artifacts / original[key]) != original[key + 'SHA256']:
            raise ValueError('Input guest integrity mismatch')
    runtime = runtime or original.get('guestRuntimeImage')
    if not runtime or not runtime.startswith('sha256:') or len(runtime) != 71:
        raise ValueError('A pinned rootfs runtime image is required')
    inspection = json.loads(docker('image', 'inspect', runtime, capture=True))[0]
    if inspection['Id'] != runtime or inspection['Architecture'] != 'arm64':
        raise ValueError('Rootfs runtime identity mismatch')
    actual = docker('run', '--rm', '--network', 'none', '--read-only', '--cap-drop', 'ALL',
                    '--security-opt', 'no-new-privileges', '--memory', '512m', '--pids-limit', '128',
                    '--entrypoint', 'sha256sum', runtime, '/system.ext4', '/rootfs/opt/artex/artex',
                    capture=True).splitlines()
    if [line.split()[0] for line in actual] != [original['systemDiskSHA256'], original['backendSHA256']]:
        raise ValueError('Runtime differs from the supplied guest')
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    with tempfile.TemporaryDirectory(prefix='skill-overlay-', dir=output.parent) as temp:
        context = Path(temp)
        shutil.copyfile(SKILL, context / 'api-recon.SKILL.md')
        parent = 'artex-skill-parent:' + uuid.uuid4().hex
        docker('tag', runtime, parent)
        try:
            recipe = f"""FROM {parent}
COPY api-recon.SKILL.md /rootfs/opt/artex/skills/api-recon/SKILL.md
RUN --network=none echo '{digest(SKILL)}  /rootfs/opt/artex/skills/api-recon/SKILL.md' | sha256sum -c - \\
    && unlink /system.ext4 && truncate -s 768M /system.ext4 \\
    && mkfs.ext4 -q -F -L artex-system -O ^has_journal -d /rootfs /system.ext4
"""
            (context / 'Dockerfile').write_text(recipe)
            docker('buildx', 'build', '--builder', 'desktop-linux', '--load',
                   '--platform', 'linux/arm64', '--pull=false', '--network', 'none',
                   '--iidfile', context / 'image.id', context)
            image = (context / 'image.id').read_text().strip()
            if docker('image', 'inspect', parent, '--format', '{{.Id}}', capture=True) != runtime:
                raise ValueError('Build parent changed')
            container = docker('create', '--network', 'none', image, capture=True)
            try:
                docker('cp', container + ':/system.ext4', output / original['systemDisk'])
                docker('cp', container + ':/rootfs/opt/artex/skills/api-recon/SKILL.md', context / 'extracted.md')
            finally:
                docker('rm', container)
            if (context / 'extracted.md').read_bytes() != SKILL.read_bytes():
                raise ValueError('Bundled skill differs from the reviewed override')
        finally:
            docker('image', 'rm', parent)
    for key in ('kernel', 'initramfs'):
        shutil.copyfile(artifacts / original[key], output / original[key])
    manifest = dict(original)
    manifest.update(systemDiskSHA256=digest(output / original['systemDisk']),
                    guestRuntimeImage=image, skillOverrides=declaration(),
                    skillOverrideParentImage=runtime,
                    skillOverrideParentManifestSHA256=digest(artifacts / 'manifest.json'),
                    skillOverrideRecipeSHA256=hashlib.sha256(recipe.encode()).hexdigest())
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    verify_manifest(output / 'manifest.json')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', type=Path)
    parser.add_argument('--artifacts', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--runtime-image')
    args = parser.parse_args()
    if args.verify:
        verify_manifest(args.verify)
    elif args.artifacts and args.output:
        build(args.artifacts, args.output, args.runtime_image)
    else:
        parser.error('Use --verify MANIFEST or --artifacts INPUT --output NEW_OUTPUT')
