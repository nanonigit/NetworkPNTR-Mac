"""Run the pinned history oracle in an owned, offline Docker reference."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import uuid

from captured_reference_host import DOCKER, ROOT, RUNTIME, create_arguments, local_context
from evidence_reference_host import SETUP, builder_is_local

LABEL = 'com.nanonigit.artex.fixture'
RECIPE = """FROM {parent}
USER 0
RUN adduser -D -H -h /state/home -u 1000 toolrunfixture && ln -sf /state/auth/jwt.key /opt/artex/jwt.key
USER 1000:1000
LABEL {label}={owner}
"""
INSTALL = """
import json, pathlib, sys
folder = pathlib.Path('/state/tools')
folder.mkdir(mode=0o700)
for name, source in json.load(sys.stdin).items():
    with (folder / name).open('x', encoding='utf-8') as stream:
        stream.write(source)
"""
EXECUTE = """
import json, os, runpy, sys
with open('/state/environment.json') as stream:
    os.environ.update(json.load(stream))
os.environ['ARTEX_TOOL_RUN_FIXTURE'] = '1'
sys.path.insert(0, '/state/tools')
runpy.run_module('tool_run_fixture', run_name='__main__')
"""


def docker(*args, data=None, timeout=100):
    result = subprocess.run([*DOCKER, *args], input=data, stdout=subprocess.PIPE, timeout=timeout, check=True)
    return result.stdout


def main():
    if not local_context(docker('context', 'inspect', 'desktop-linux', '--format', '{{.Endpoints.docker.Host}}').decode().strip()):
        raise RuntimeError('Tool history requires a local Docker context')
    if not builder_is_local(docker('buildx', 'inspect', 'desktop-linux').decode()):
        raise RuntimeError('Tool history requires the local Docker builder')
    if docker('image', 'inspect', RUNTIME, '--format', '{{.Id}}').decode().strip() != RUNTIME:
        raise RuntimeError('Pinned tool history runtime image is unavailable')

    owner = uuid.uuid4().hex
    tag = 'artex-toolrun-reference:' + owner
    parent = 'artex-toolrun-parent:' + owner
    container_name = 'artex-toolrun-' + owner[:12]
    label_filter = LABEL + '=' + owner
    files = {'check_network.py': ROOT / 'guest/check_network.py'}
    for name in ('tool_run_fixture.py', 'findings_seed_guest.py', 'chat_upload_contract_fixture.py'):
        files[name] = ROOT / 'script' / name
    bundle = {name: path.read_text(encoding='utf-8') for name, path in files.items()}
    try:
        docker('tag', RUNTIME, parent)
        with tempfile.TemporaryDirectory(prefix='artex-toolrun-') as build:
            (Path(build) / 'Dockerfile').write_text(RECIPE.format(parent=parent, label=LABEL, owner=owner))
            docker('buildx', 'build', '--builder', 'desktop-linux', '--load', '--platform', 'linux/arm64',
                   '--pull=false', '--network', 'none', '-t', tag, build, timeout=180)
        if docker('image', 'inspect', parent, '--format', '{{.Id}}').decode().strip() != RUNTIME:
            raise RuntimeError('Pinned tool history runtime alias changed')
        image = docker('image', 'inspect', tag, '--format', '{{.Id}}').decode().strip()
        args = create_arguments(container_name, owner, tag)
        args[-1:] = ['--pull', 'never', '--entrypoint', '/bin/sleep', image, '240']
        try:
            container = docker(*args).decode().strip()
            docker('start', container)
            docker('exec', '-i', container, 'python3', '-', data=SETUP.encode())
            docker('exec', '-i', container, 'python3', '-c', INSTALL, data=json.dumps(bundle).encode())
            proof = json.loads(docker('exec', container, 'python3', '-c', EXECUTE))
        finally:
            # Recover ownership by name and label if create did not return an ID.
            owned = docker('ps', '-aq', '--no-trunc', '--filter', f'name=^/{container_name}$',
                           '--filter', 'label=' + label_filter).decode().split()
            for identity in owned:
                docker('rm', '-fv', identity, timeout=30)
            if len(owned) != 1:
                raise RuntimeError('Disposable tool history container identity was not confirmed')
    finally:
        try:
            if docker('image', 'ls', '-q', '--filter', 'label=' + label_filter, tag).strip():
                docker('image', 'rm', tag, timeout=30)
        finally:
            if docker('image', 'ls', '-q', parent).strip():
                if docker('image', 'inspect', parent, '--format', '{{.Id}}').decode().strip() != RUNTIME:
                    raise RuntimeError('Disposable tool history runtime alias owner changed')
                docker('image', 'rm', parent, timeout=30)
    proof.update(containerRemoved=True, referenceParentImage=RUNTIME, referenceImage=image,
                 sourceSHA256={name: hashlib.sha256(value.encode()).hexdigest() for name, value in bundle.items()})
    print(json.dumps(proof, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
