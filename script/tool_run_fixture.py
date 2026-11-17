"""Synthetic tool history and API oracle for an offline disposable NetworkPNTR backend."""
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
from urllib.parse import urlencode

from chat_upload_contract_fixture import Client, require
import check_network
from findings_seed_guest import EMPTY_TABLES, validate_environment

SOURCE_COMMIT = 'e75ae371ad777ffd1eecdd28d2781a6519b05591'
REFERENCE_BACKEND = '0ebad83ddda276b03b415d64ce30af44e7a587860f3b660c12563462a0ac5e80'
STAMP = '2026-10-22T10:00:00Z'
KEYWORD = "日本語+ O'Neil"
TOOLS = ('Bash', 'Read', 'WebFetch')
RUNS = tuple({
    'id': 9200 + i * 2,
    'exploration_id': 8801 if i < 28 else 8802,
    'worker': f'fixture-worker-{i % 2}',
    'tool': TOOLS[i % 3],
    'command': json.dumps(
        {'command' if i % 3 == 0 else 'fixture_input': f'{KEYWORD if i % 5 == 0 else "plain"} {i}'},
        ensure_ascii=False),
    'output': '' if i % 7 == 0 else f'<literal> result {i}\n結果',
    'is_error': i % 7 != 0 and i % 4 == 0,
    'created_at': STAMP,
} for i in range(54))


def quote(value):
    return "'" + value.replace("'", "''") + "'"


def seed_sql():
    locked = ', '.join(EMPTY_TABLES)
    occupied = ' OR '.join(f'EXISTS (SELECT 1 FROM {table})' for table in EMPTY_TABLES)
    statements = [
        'BEGIN;', "SET LOCAL lock_timeout = '2s';", "SET LOCAL statement_timeout = '5s';",
        'SET LOCAL standard_conforming_strings = on;',
        f'LOCK TABLE {locked} IN EXCLUSIVE MODE;',
        f"DO $$ BEGIN IF {occupied} THEN RAISE EXCEPTION 'fresh fixture required'; END IF; END; $$;",
        "INSERT INTO explorations(id,description,goal,status) VALUES "
        "(8801,'Tool history fixture A','Synthetic rows only','achieved'),"
        "(8802,'Tool history fixture B','Synthetic rows only','achieved');",
    ]
    values = []
    for run in RUNS:
        identifier = run['id']
        call = quote(f'tool-history-fixture-{identifier}')
        prefix = f"{run['exploration_id']},{quote(run['worker'])},{quote(run['tool'])},{call}"
        values.append(f"({identifier},{prefix},'tool_use',{quote(run['command'])},false,{quote(STAMP)})")
        if run['output']:
            error = 'true' if run['is_error'] else 'false'
            values.append(f"({identifier + 1},{prefix},'tool_result',{quote(run['output'])},{error},{quote(STAMP)})")
    statements += [
        'INSERT INTO activity(id,exploration_id,worker,tool,tool_use_id,kind,detail,is_error,created_at) VALUES '
        + ',\n'.join(values) + ';',
        f'ALTER SEQUENCE activity_id_seq RESTART WITH {RUNS[-1]["id"] + 2};',
        'ALTER SEQUENCE explorations_id_seq RESTART WITH 8803;',
        'COMMIT;',
    ]
    return '\n'.join(statements)


def seed():
    require(os.environ.get('ARTEX_TOOL_RUN_FIXTURE') == '1', 'explicit tool history fixture required')
    network = check_network.inspect()
    require(check_network.is_isolated(network), 'tool history fixture network')
    result = subprocess.run(['/usr/libexec/postgresql16/psql', '-X', '--no-password', '-q', '-v', 'ON_ERROR_STOP=1'],
                            input=seed_sql().encode(), env=validate_environment(), stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, timeout=15)
    require(result.returncode == 0, 'tool history seed transaction')


def snapshot(client):
    snapshots = {}
    for name, task, keyword, rows in (
        ('all', None, None, RUNS),
        ('exploration', 8801, None, RUNS[:28]),
        ('keyword', None, KEYWORD, RUNS[::5]),
        ('combined', 8802, KEYWORD, tuple(run for run in RUNS[::5] if run['exploration_id'] == 8802)),
        ('tool', None, 'WebFetch', tuple(run for run in RUNS if run['tool'] == 'WebFetch')),
        ('empty', 9999, None, ()),
    ):
        filters = {key: value for key, value in (('task', task), ('q', keyword)) if value is not None}
        expected = list(reversed(rows))
        counts = [{'tool': tool, 'total': len(group), 'errors': sum(run['is_error'] for run in group)}
                  for tool in TOOLS if (group := [run for run in rows if run['tool'] == tool])]
        counts.sort(key=lambda row: (-row['total'], row['tool']))
        stats_path = '/api/commands/stats' + ('?' + urlencode(filters) if filters else '')
        observed = []
        for page, size in ((0, 25), (1, 25), (2, 25), (0, 50), (0, 100)):
            start = page * size
            result = client.api('GET', '/api/commands?' + urlencode(dict(filters, page=page, size=size)))
            require(result == {'commands': expected[start:start + size], 'total': len(rows)},
                    f'tool history rows: {name} page={page} size={size}')
            observed.append(result)
        stats = client.api('GET', stats_path)
        require(stats == {'stats': counts}, 'tool history aggregate: ' + name)
        digest = hashlib.sha256(json.dumps([observed, stats], sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        snapshots[name] = {'rows': len(rows), 'pagesChecked': len(observed), 'stats': counts, 'snapshotSHA256': digest}
    return snapshots


def main():
    require(os.environ.get('ARTEX_DISPOSABLE_REFERENCE') == '1', 'explicit disposable reference required')
    validate_environment()
    network = check_network.inspect()
    require(check_network.is_isolated(network), 'reference isolation')
    data = Path('/state/app/data')
    require(not data.is_symlink() and not any(data.iterdir()), 'fresh reference data required')
    backend = Path('/opt/artex/artex')
    with backend.open('rb') as binary:
        backend_hash = hashlib.file_digest(binary, 'sha256').hexdigest()
    require(backend_hash == REFERENCE_BACKEND, 'pinned reference executable')
    environment = dict(os.environ, ARTEX_SETUP_TOKEN=secrets.token_hex(32), ARTEX_LANG='en',
                       ARTEX_SKILL_DIR='/opt/artex/skills')
    with subprocess.Popen([str(backend), '-addr', '127.0.0.1:8787', '-data', str(data), '-proxy', ''],
                          cwd=data, env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as process:
        try:
            client = Client()
            for _ in range(100):
                require(process.poll() is None, 'reference startup')
                try:
                    auth = client.api('GET', '/api/auth/status')
                    break
                except OSError:
                    time.sleep(.2)
            else:
                raise RuntimeError('reference readiness exhausted')
            require(auth.get('initialized') is False and auth.get('setup_token_required') is True, 'reference fresh auth')
            for path in ('/api/commands', '/api/commands/stats'):
                require(client.request('GET', path)[0] == 401, 'tool history authentication')
            client.token = client.api('POST', '/api/auth/init', {
                'password': secrets.token_hex(32), 'setup_token': environment['ARTEX_SETUP_TOKEN']
            })['token']
            require(client.api('GET', '/api/commands') == {'commands': [], 'total': 0}, 'initial empty history')
            require(client.api('GET', '/api/commands/stats') == {'stats': []}, 'initial empty aggregate')
            seed()
            try:
                seed()
            except RuntimeError as error:
                require(str(error).endswith('tool history seed transaction'), 'second seed failure')
            else:
                raise RuntimeError('Tool history refused to reject a second seed')
            cases = snapshot(client)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
    require(process.returncode == 0, 'reference cooperative stop')
    print(json.dumps(dict(sourceCommit=SOURCE_COMMIT, backendSHA256=backend_hash, network=network,
                          protectedStatuses=[401, 401], freshEmpty=True, reseedRejected=True, cooperativeStop=True, cases=cases)))


if __name__ == '__main__':
    main()
