#!/usr/bin/env python3
"""Compare native metrics with independent browser calculations and a disposable pinned backend."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
import uuid
from compare_backend import BACKEND_IMAGE, POSTGRES_IMAGE, run
from dashboard_seed_guest import SQL

ROOT = Path(__file__).resolve().parent


def metrics(snapshot):
    return json.loads(subprocess.check_output(['node', str(ROOT / 'dashboard_browser_metrics.mjs')], input=json.dumps(snapshot).encode()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixture_directory', type=Path)
    parser.add_argument('output_directory', type=Path)
    args = parser.parse_args()
    vm = json.loads((args.fixture_directory / 'dashboard-contract-vm.json').read_text())
    vm_snapshot = json.loads((args.fixture_directory / 'dashboard-snapshot-vm.json').read_text())
    if metrics(vm_snapshot) != vm:
        raise RuntimeError('Native metrics differ from the independent pinned-browser translation')
    identity = 'artex-dashboard-' + uuid.uuid4().hex[:12]
    network, postgres, app = identity + '-net', identity + '-db', identity + '-app'
    env = dict(os.environ, POSTGRES_PASSWORD=secrets.token_hex(32), ARTEX_SETUP_TOKEN=secrets.token_hex(32), DASHBOARD_FIXTURE_PASSWORD=secrets.token_hex(24))
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
            raise RuntimeError('Reference database readiness failed')
        run('docker', 'run', '-d', '--name', app, '--network', network, '--read-only', '--user', '1000:1000', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true', '--tmpfs', '/state:rw,nosuid,nodev,size=256m,uid=1000,gid=1000,mode=700', '--tmpfs', '/tmp:rw,noexec,nosuid,nodev,size=64m', '--workdir', '/tmp', '-e', 'ARTEX_PG_DSN', '-e', 'ARTEX_SETUP_TOKEN', '-e', 'DASHBOARD_FIXTURE_PASSWORD', '--entrypoint', '/bin/sh', BACKEND_IMAGE, '-c', 'mkdir -p /state/home /state/data; exec /opt/artex/artex -addr 127.0.0.1:8787 -data /state/data -proxy ""', env=env, stdout=subprocess.DEVNULL)
        created.append(app)
        code = (ROOT / 'dashboard_reference_fixture.py').read_bytes()
        subprocess.run(['docker', 'exec', '-i', app, 'python3', '-', 'prepare'], input=code, check=True, stdout=subprocess.DEVNULL)
        # Only the disposable named database is seeded; SQL and credentials never enter shell text.
        subprocess.run(['docker', 'exec', '-i', postgres, 'psql', '-X', '-q', '-U', 'artex', '-d', 'artex', '-v', 'ON_ERROR_STOP=1'], input=SQL.encode(), check=True, stdout=subprocess.DEVNULL)
        # Reload the manager's in-memory task list from the same disposable PostgreSQL database.
        run('docker', 'restart', app, stdout=subprocess.DEVNULL)
        raw = subprocess.check_output(['docker', 'exec', '-i', app, 'python3', '-', 'collect'], input=code)
        actual = metrics(json.loads(raw))
        args.output_directory.mkdir(parents=True, exist_ok=True)
        for name, value in [('metrics-vm.json', vm), ('metrics-reference.json', actual)]:
            (args.output_directory / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
        if actual != vm:
            raise RuntimeError('VM and reference dashboard metrics differ; inspect normalized evidence')
        (args.output_directory / 'comparison.json').write_text(json.dumps({
            'baseline': 'e75ae371ad777ffd1eecdd28d2781a6519b05591', 'native_matches_independent_browser_math': True,
            'vm_matches_disposable_reference': True, 'nonempty_data': True, 'token_scenarios': len(vm['scenarios']),
            'existing_browser_data_modified': False, 'traffic_capture_runtime': 'pending; both fixture runtimes disable the proxy',
            'external_ui_acceptance': 'pending'}, indent=2) + '\n')
        print('PASS nonempty VM dashboard matches independent browser calculations and disposable reference backend.')
    finally:
        for name in reversed(created):
            subprocess.run(['docker', 'rm', '-f', name], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['docker', 'network', 'rm', network], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
