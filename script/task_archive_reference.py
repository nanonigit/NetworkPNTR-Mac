"""Finite independent API exercise for a fresh, network-none reference container."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import secrets
import subprocess
import time
from urllib.parse import quote

from chat_upload_contract_fixture import Client, require
import task_archive_seed_guest as seed
import task_archive_fixture_control as control

CHECKS = ['initial_terminal_tasks', 'initial_workspace_bytes', 'bulk_archive_accepted', 'bulk_archive_ready',
          'live_rows_removed', 'workspace_files_removed', 'restore_failure_observed', 'explicit_retry_accepted',
          'first_task_restored', 'first_workspace_restored', 'second_delete_accepted', 'second_archive_removed',
          'first_rearchive_accepted', 'first_ready_for_restart', 'persisted_archive_ready',
          'restart_restore_accepted', 'restart_task_restored', 'restart_workspace_restored', 'second_task_stays_deleted']


def poll_archive(read, identifier, task, desired, waiting, *, sleep=time.sleep, clock=time.monotonic):
    deadline = clock() + 45
    for _ in range(120):
        require(clock() <= deadline, 'reference archive deadline')
        status, row = read()
        require(clock() <= deadline, 'reference archive late response')
        if status == 404 and desired is None:
            return None
        require(status == 200 and isinstance(row, dict) and type(row.get('id')) is int and row['id'] == identifier
                and type(row.get('task_id')) is int and row['task_id'] == task, 'reference archive identity')
        if desired is not None and row.get('state') == desired:
            return row
        require(row.get('state') in waiting, 'reference archive terminal state')
        sleep(.2)
    raise RuntimeError('Reference archive polling exhausted')


def files(client, tasks, present):
    proofs = []
    for name, data in seed.FILES:
        if int(name.split('/')[1]) not in tasks:
            continue
        status, actual = client.request('GET', '/api/workspace/download?path=' + quote(name, safe=''), binary=True)
        require(status == (200 if present else 404) and (not present or actual == data), 'reference workspace bytes')
        if present:
            proofs.append({'path': name, 'size': len(data), 'sha256': hashlib.sha256(actual).hexdigest()})
    return proofs


def task_metadata(row, identifier):
    require(row.get('id') == str(identifier) and row.get('exploration_id') == identifier and row.get('status') == 'done'
            and row.get('paused') is False and row.get('queued') is False and row.get('in_flight') == 0
            and row.get('llm_profile_id') is None and row.get('active_llm_profile_id') is None
            and not row.get('llm_profile_ids') and not row.get('source_task_ids') and row.get('category_id') == 7100
            and row.get('category_name') == 'T17 archive category' and row.get('goal') == seed.GOAL
            and row.get('name') == (seed.NAME if identifier == 7101 else 'T17 second')
            and row.get('description') == (seed.DESCRIPTION if identifier == 7101 else 'Archive fixture second'), 'reference task metadata')


def live(client, expected):
    deadline = time.monotonic() + 45
    for _ in range(120):
        require(time.monotonic() <= deadline, 'reference live deadline')
        value = client.api('GET', '/api/tasks')
        require(time.monotonic() <= deadline, 'reference late live response')
        rows = value.get('tasks') or []
        require(isinstance(rows, list), 'reference task list')
        ids = {row.get('id') for row in rows}; active = value.get('active')
        require(ids <= {'7101', '7102'} and active in (None, '', '7101', '7102'), 'reference foreign task')
        if ids == {str(i) for i in expected} and active in (None, '', *[str(i) for i in expected]):
            for row in rows:
                task_metadata(row, int(row['id']))
            return
        time.sleep(.2)
    raise RuntimeError('Reference live polling exhausted')


def page(client, count, identifier=None):
    result = client.api('GET', '/api/task-archives?page=1&size=20')
    require('items' in result and (result['items'] is None or isinstance(result['items'], list)), 'reference archive items')
    rows = result['items'] or []
    require(result.get('page') == 1 and result.get('size') == 20 and result.get('total') == count
            and len(rows) == count, 'reference archive page')
    if identifier is not None:
        require(rows[0].get('id') == identifier, 'reference persisted page owner')
    return rows


def ready(row, task):
    require(row.get('task_id') == task and row.get('state') == 'ready' and row.get('progress') == 100
            and row.get('original_status') == 'done' and not row.get('error') and not row.get('warnings')
            and row.get('original_size', 0) > 0 and row.get('compressed_size', 0) > 0
            and isinstance(row.get('sha256'), str) and re.fullmatch('[0-9a-f]{64}', row['sha256']) is not None
            and row.get('data_counts', {}).get('tasks') == 1 and row.get('data_counts', {}).get('explorations') == 1
            and row.get('category_id') == 7100 and row.get('category_name') == 'T17 archive category'
            and row.get('task_name') == (seed.NAME if task == 7101 else 'T17 second')
            and row.get('task_description') == (seed.DESCRIPTION if task == 7101 else 'Archive fixture second')
            and row.get('task_goal') == seed.GOAL, 'reference ready metadata')


def wait(client, identifier, task, state, waiting):
    row = poll_archive(lambda: client.request('GET', '/api/task-archives/' + str(identifier)), identifier, task, state, waiting)
    if state == 'ready':
        ready(row, task)
    return row


def receipt(client, identifier, task, method, suffix, state):
    row = client.api(method, '/api/task-archives/' + str(identifier) + suffix, expected=202)
    require(row.get('id') == identifier and row.get('task_id') == task and row.get('state') == state, 'reference queued receipt')


def before_restart(client):
    control.audit(); live(client, {7101, 7102}); page(client, 0)
    proof = files(client, {7101, 7102}, True)
    items = client.api('POST', '/api/tasks/archive/batch', {'task_ids': ['7102', '7101']}, expected=202).get('items')
    require(isinstance(items, list) and len(items) == 2 and {row.get('id') for row in items} == {'7101', '7102'}
            and all(row.get('ok') is True and row.get('queued') is True and type(row.get('archive_id')) is int
                    and row['archive_id'] > 0 for row in items), 'reference batch receipt')
    ids = {int(row['id']): row['archive_id'] for row in items}; require(len(set(ids.values())) == 2, 'reference distinct archives')
    for task, identifier in ids.items():
        wait(client, identifier, task, 'ready', {'archive_queued', 'archiving'})
    live(client, set()); files(client, {7101, 7102}, False)
    first, second = ids[7101], ids[7102]; row = client.api('GET', '/api/task-archives/' + str(first)); ready(row, 7101)
    digest = row['sha256']; control.set_package_hidden(True, first, digest)
    receipt(client, first, 7101, 'POST', '/restore', 'restore_queued')
    failed = wait(client, first, 7101, 'restore_failed', {'restore_queued', 'restoring'})
    require(isinstance(failed.get('error'), str) and bool(failed['error']), 'reference restore fault')
    control.set_package_hidden(False, first, digest)
    receipt(client, first, 7101, 'POST', '/restore', 'restore_queued')
    wait(client, first, 7101, None, {'restore_queued', 'restoring'}); live(client, {7101})
    task_metadata(client.api('GET', '/api/tasks/7101'), 7101); files(client, {7101}, True)
    ready(client.api('GET', '/api/task-archives/' + str(second)), 7102)
    receipt(client, second, 7102, 'DELETE', '', 'delete_queued')
    wait(client, second, 7102, None, {'delete_queued', 'deleting'})
    require(client.request('GET', '/api/tasks/7102')[0] == 404, 'reference deleted task')
    require(client.request('GET', '/api/workspace/download?path=' + quote('archives/tasks/task-7102-' + str(second) + '.tar.zst', safe=''), binary=True)[0] == 404, 'reference deleted package')
    queued = client.api('POST', '/api/tasks/7101/archive', expected=202)
    require(queued.get('task_id') == 7101 and queued.get('state') == 'archive_queued' and type(queued.get('id')) is int and queued['id'] > 0, 'reference rearchive receipt')
    row = wait(client, queued['id'], 7101, 'ready', {'archive_queued', 'archiving'}); live(client, set())
    ready(page(client, 1, row['id'])[0], 7101); control.audit()
    return {'archive_id': row['id'], 'sha256': row['sha256'], 'files': proof}


def after_restart(client, checkpoint):
    control.audit(); live(client, set()); identifier = checkpoint['archive_id']
    ready(page(client, 1, identifier)[0], 7101)
    row = client.api('GET', '/api/task-archives/' + str(identifier)); ready(row, 7101)
    require(row['sha256'] == checkpoint['sha256'], 'reference persisted package digest')
    receipt(client, identifier, 7101, 'POST', '/restore', 'restore_queued')
    wait(client, identifier, 7101, None, {'restore_queued', 'restoring'}); live(client, {7101})
    restored = client.api('GET', '/api/tasks/7101'); task_metadata(restored, 7101); files(client, {7101}, True)
    require(client.request('GET', '/api/tasks/7102')[0] == 404, 'reference second stays deleted')
    files(client, {7102}, False); page(client, 0); control.audit()
    return {'checks': CHECKS, 'files': checkpoint['files'], 'taskName': restored['name'], 'taskDescription': restored['description'], 'passed': True}


def main():
    require(platform.system() == 'Linux' and os.getuid() == 1000 and os.environ.get('ARTEX_DISPOSABLE_REFERENCE') == '1', 'reference isolation')
    seed.validate_environment()
    client = Client(); process = None; logs = []; checkpoint = None; result = None
    try:
        for index in range(1, 4):
            environment = dict(os.environ, ARTEX_SETUP_TOKEN=secrets.token_hex(32), ARTEX_LANG='en')
            log = Path('/state/app') / ('reference-boot-' + str(index) + '.log'); logs.append(log)
            with log.open('xb') as stream:
                process = subprocess.Popen(['/opt/artex/artex', '-addr', '127.0.0.1:8787', '-data', str(seed.DATA_ROOT), '-proxy', ''], cwd=seed.DATA_ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT)
            for _ in range(120):
                require(process.poll() is None, 'reference backend died')
                try:
                    status, auth = Client().request('GET', '/api/auth/status')
                    if status == 200:
                        break
                except (OSError, ValueError):
                    pass
                time.sleep(.25)
            else:
                raise RuntimeError('Reference backend readiness exhausted')
            require(Client().request('GET', '/api/llm/profiles')[0] == 401, 'reference protected API')
            if index == 1:
                require(auth.get('initialized') is False and auth.get('setup_token_required') is True, 'reference fresh authentication')
                client.token = client.api('POST', '/api/auth/init', {'password': secrets.token_hex(32), 'setup_token': environment['ARTEX_SETUP_TOKEN']})['token']
                control.audit()
                with contextlib.redirect_stdout(io.StringIO()):
                    seed.main()
                control.audit()
            else:
                require(auth.get('initialized') is True, 'reference persisted authentication')
                client.api('GET', '/api/llm/profiles')  # Existing bearer, no login fallback.
                if index == 2:
                    checkpoint = before_restart(client)
                else:
                    result = after_restart(client, checkpoint)
            process.terminate(); code = process.wait(timeout=20); process = None
            require(code == 0, 'reference cooperative backend stop')
        require(result is not None and result['passed'], 'reference complete result')
        print(json.dumps({'exercise': result, 'backend_starts': 3, 'cooperative_stops': 3, 'fresh_setup': True, 'persisted_session': True}, ensure_ascii=False))
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=5)


if __name__ == '__main__':
    main()
