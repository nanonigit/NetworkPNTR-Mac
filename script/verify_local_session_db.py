#!/usr/bin/env python3
"""Run native-session Go integration tests against a disposable private PostgreSQL."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
from build_local_session import docker, preflight, ENV, DOCKER
from compare_backend import POSTGRES_IMAGE
from verify_mcp_task_fixture import cleanup_owned, OWNER_LABEL


def verify(image):
    preflight()
    record = json.loads(docker('image', 'inspect', image))[0]
    if record['Id'] != image or record['Architecture'] != 'arm64':
        raise ValueError('Pinned local test image required')
    docker('image', 'inspect', POSTGRES_IMAGE)
    owner = secrets.token_hex(16)
    network, database, runner = ['networkpntr-session-' + owner + '-' + name for name in ('net', 'db', 'test')]
    env = dict(ENV, POSTGRES_PASSWORD=secrets.token_hex(32))
    env['ARTEX_PG_DSN'] = 'postgres://artex:' + env['POSTGRES_PASSWORD'] + '@postgres:5432/artex?sslmode=disable'
    failure = None
    try:
        docker('network', 'create', '--internal', '--label', OWNER_LABEL + '=' + owner, network)
        subprocess.run([*DOCKER, 'run', '-d', '--name', database, '--label', OWNER_LABEL + '=' + owner,
            '--pull=never', '--network', network, '--network-alias', 'postgres', '--read-only', '--user', '999:999',
            '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true', '--pids-limit', '128', '--memory', '768m',
            '--tmpfs', '/var/lib/postgresql/data:rw,noexec,nosuid,nodev,size=512m,uid=999,gid=999,mode=700',
            '--tmpfs', '/var/run/postgresql:rw,noexec,nosuid,nodev,size=16m,uid=999,gid=999',
            '--tmpfs', '/tmp:rw,noexec,nosuid,nodev,size=16m', '-e', 'POSTGRES_PASSWORD', '-e', 'POSTGRES_USER=artex',
            '-e', 'POSTGRES_DB=artex', POSTGRES_IMAGE], env=env, check=True, stdout=subprocess.DEVNULL, timeout=30)
        for _ in range(60):
            result = subprocess.run([*DOCKER, 'exec', database, 'pg_isready', '-U', 'artex', '-d', 'artex'], env=ENV,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            if result.returncode == 0:
                break
            time.sleep(.5)
        else:
            raise RuntimeError('Database readiness failed')
        result = subprocess.run([*DOCKER, 'run', '--name', runner, '--label', OWNER_LABEL + '=' + owner,
            '--pull=never', '--network', network, '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
            '--pids-limit', '256', '--memory', '3g', '-e', 'ARTEX_PG_DSN', '-e', 'GOMAXPROCS=2',
            '--entrypoint', 'go', image, 'test', '-p', '2', '-mod=readonly', './server', '-run', 'Native', '-count=1', '-json'],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
        # Never persist raw test output or database credentials.
        events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith(b'{')]
        tests = [event['Test'] for event in events if event.get('Action') == 'pass' and 'Test' in event]
        skips = [event['Test'] for event in events if event.get('Action') == 'skip']
        if result.returncode != 0 or skips or len([name for name in tests if name.endswith('DB')]) < 4:
            failure = {'exitCode': result.returncode, 'skipped': len(skips),
                       'failedTests': [event.get('Test', 'package') for event in events if event.get('Action') == 'fail']}
            raise RuntimeError('Native database tests failed: ' + json.dumps(failure))
    finally:
        cleanup = cleanup_owned(owner, network, [runner, database])
        if not cleanup['verified']:
            raise RuntimeError('Owned database fixture cleanup failed')
    return {'backendBuildImage': image, 'passedTests': tests, 'skippedTests': 0, 'cleanupVerified': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image-id-file', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.image_id_file.read_text().strip()), indent=2))
