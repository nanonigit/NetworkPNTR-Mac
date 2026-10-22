#!/usr/bin/env python3
"""Compare VM contracts with a disposable pinned browser-backend fixture."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
import uuid
from prepare_backend import BACKEND_IMAGE

POSTGRES_IMAGE = 'postgres:16-bookworm@sha256:d81f7b51697014367236d07ec58b54153fc28f828b72bf247fe5c7487520bcb0'
FIXTURE = r'''
import json, os, secrets, time, urllib.request, urllib.error

def request(method, path, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token: headers['Authorization'] = 'Bearer ' + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request('http://127.0.0.1:8787' + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)
for _ in range(120):
    try:
        status, auth = request('GET', '/api/auth/status')
        if status == 200: break
    except (OSError, ValueError): pass
    time.sleep(.5)
else: raise SystemExit('Reference backend readiness failed')
protected, _ = request('GET', '/api/llm/profiles')
password = secrets.token_hex(24)
wrong, _ = request('POST', '/api/auth/init', {'password': password, 'setup_token': 'wrong'})
setup, session = request('POST', '/api/auth/init', {'password': password, 'setup_token': os.environ['ARTEX_SETUP_TOKEN']})
if setup != 200 or 'token' not in session: raise SystemExit('Reference setup failed')
fixture = {'name': 'Native parity fixture', 'format': 'openai', 'base_url': 'https://api.openai.com/v1', 'model': 'fixture-no-request', 'api_key': '', 'streaming': False, 'context_window_k': 64, 'max_tokens': 256, 'pool_exclude': True}
saved, _ = request('POST', '/api/llm/profiles', fixture, session['token'])
listed, result = request('GET', '/api/llm/profiles', token=session['token'])
if listed != 200: raise SystemExit('Reference profile read failed')
first = next(profile for profile in result['profiles'] if profile['name'] == fixture['name'])
profile = {key: first[key] for key in fixture if key != 'api_key'}
print(json.dumps({'initial_auth': auth, 'protected_status': protected, 'wrong_setup_status': wrong, 'setup_status': setup, 'profile_status': saved, 'profile': profile}, sort_keys=True))
'''


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('vm_contract', type=Path)
    parser.add_argument('output_directory', type=Path)
    args = parser.parse_args()
    expected = json.loads(args.vm_contract.read_text())
    identity = 'artex-mac-parity-' + uuid.uuid4().hex[:12]
    network = identity + '-net'
    postgres = identity + '-db'
    app = identity + '-app'
    env = dict(os.environ, POSTGRES_PASSWORD=secrets.token_hex(32), ARTEX_SETUP_TOKEN=secrets.token_hex(32))
    env['ARTEX_PG_DSN'] = 'postgres://artex:' + env['POSTGRES_PASSWORD'] + '@postgres:5432/artex?sslmode=disable'
    created = []
    try:
        run('docker', 'network', 'create', '--internal', network, stdout=subprocess.DEVNULL)
        run('docker', 'run', '-d', '--name', postgres, '--network', network, '--network-alias', 'postgres', '--read-only', '--user', '999:999', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true', '--tmpfs', '/var/lib/postgresql/data:rw,noexec,nosuid,nodev,size=512m,uid=999,gid=999,mode=700', '--tmpfs', '/var/run/postgresql:rw,noexec,nosuid,nodev,size=16m,uid=999,gid=999', '--tmpfs', '/tmp:rw,noexec,nosuid,nodev,size=16m', '-e', 'POSTGRES_PASSWORD', '-e', 'POSTGRES_USER=artex', '-e', 'POSTGRES_DB=artex', POSTGRES_IMAGE, env=env, stdout=subprocess.DEVNULL)
        created.append(postgres)
        for _ in range(120):
            result = subprocess.run(['docker', 'exec', postgres, 'pg_isready', '-U', 'artex', '-d', 'artex'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if result.returncode == 0:
                break
            time.sleep(.5)
        else:
            raise RuntimeError('Reference PostgreSQL readiness failed')
        run('docker', 'run', '-d', '--name', app, '--network', network, '--read-only', '--user', '1000:1000', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true', '--tmpfs', '/state:rw,nosuid,nodev,size=256m,uid=1000,gid=1000,mode=700', '--tmpfs', '/tmp:rw,noexec,nosuid,nodev,size=64m', '--workdir', '/tmp', '-e', 'ARTEX_PG_DSN', '-e', 'ARTEX_SETUP_TOKEN', '--entrypoint', '/bin/sh', BACKEND_IMAGE, '-c', 'mkdir -p /state/home /state/data; exec /opt/artex/artex -addr 127.0.0.1:8787 -data /state/data -proxy ""', env=env, stdout=subprocess.DEVNULL)
        created.append(app)
        output = subprocess.check_output(['docker', 'exec', '-i', app, 'python3', '-'], input=FIXTURE.encode())
        actual = json.loads(output)
        args.output_directory.mkdir(parents=True, exist_ok=True)
        (args.output_directory / 'api-contract-reference.json').write_text(json.dumps(actual, indent=2, sort_keys=True) + '\n')
        if actual != expected:
            raise RuntimeError('VM and pinned reference API contracts differ; inspect normalized JSON')
        (args.output_directory / 'api-contract-comparison.json').write_text(json.dumps({'baseline': 'e75ae371ad777ffd1eecdd28d2781a6519b05591', 'identical_fixture': True, 'api_contract_equal': True, 'cases': ['first_run_auth_status', 'protected_api_requires_login', 'wrong_setup_token_rejected', 'setup', 'profile_save_and_read'], 'browser_data_modified': False, 'ui_workflow_parity': 'pending'}, indent=2) + '\n')
        print('PASS VM and disposable pinned browser-backend API contracts match; existing browser data untouched.')
    finally:
        for name in reversed(created):
            subprocess.run(['docker', 'rm', '-f', name], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['docker', 'network', 'rm', network], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
