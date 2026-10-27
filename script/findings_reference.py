"""Independent fixed-backend API reference. Run only inside a fresh, offline diagnostic container."""
import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import secrets
import subprocess
import sys
import time
from urllib.parse import parse_qsl, urlencode, urlsplit

from chat_upload_contract_fixture import Client
import findings_seed_guest as seed
import findings_fixture_control as control
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'guest'))
import check_network

BASE = '/api/exploration/findings'
SOURCE_COMMIT = 'e75ae371ad777ffd1eecdd28d2781a6519b05591'
LEVELS = ('critical', 'high', 'medium', 'low')
STATUSES = ('pending', 'in_progress', 'confirmed', 'resolved', 'fixed', 'false_positive', 'ignored', 'duplicate', 'risk_accepted')
TASKS = tuple(str(t) for t in range(8101, 8112))
SCOPES = ('c:8200', 'a:8201', 'a:8202', 'a:8203', '__none__')
ASSETS = {8201: ('root_domain', 'fixture.example.test'), 8202: ('subdomain', 'api.fixture.example.test'), 8203: ('ip', '198.51.100.9')}
EDITED_NAME = "F4 edited e\u0301 \ufeff 中文 한국어 'quoted'"
EDITED_CLASS = 'F4 edited class e\u0301'
NUL_NAME = 'F4 NUL\0fixture'
JS_SPACE = ''.join(chr(n) for n in list(range(9, 14)) + [32, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF] + list(range(0x2000, 0x200B)))
SHARED_MUTATIONS = ['edited_fields', 'separate_status', 'partial_patch_http500', 'partial_patch_readback', 'final_status', 'delete_9102', 'delete_9133']
BOUNDARY_SHARED = ['single_name_normalized', 'single_class_normalized', 'single_severity', 'empty_name',
                   'diagnostic_class_8192_bytes', 'original_fields_restored']
BOUNDARY_LOCAL = ['empty_patch_rejected', 'oversized_body_rejected', 'invalid_page_rejected']
NATIVE_MUTATIONS = ['initial_cache', 'edited_fields', 'separate_status', 'partial_patch_http500', 'partial_patch_readback',
                    'uncertainty_retained_after_read', 'uncertainty_blocks_write', 'explicit_acknowledgment', 'final_status', 'delete_9102', 'delete_9133', 'final_cache']
DATA_ROOT = Path('/state/app/data')


def require(condition, message):
    if not condition:
        raise RuntimeError('Findings reference ' + message)


class Bounded:
    def __init__(self, client, *, clock=time.monotonic, maximum=128):
        require(type(maximum) is int and 1 <= maximum <= 128, 'request limit')
        self.client, self.clock, self.maximum = client, clock, maximum
        self.deadline, self.calls, self.audits = clock() + 90, 0, []

    def check(self):
        require(self.clock() <= self.deadline and self.calls <= self.maximum, 'stage deadline/count')

    def request(self, method, path, body=None):
        self.check()
        require(self.calls < self.maximum and self.valid(method, path, body), 'unsafe request')
        self.calls += 1
        result = self.client.request(method, path, body)
        self.check()
        return result

    def api(self, method, path, body=None, expected=200):
        status, value = self.request(method, path, body)
        require(status == expected, 'API status')
        return value

    def audit(self):
        self.check(); proof = control.audit(); self.check(); self.audits.append(proof)

    @staticmethod
    def valid(method, path, body):
        try:
            url = urlsplit(path)
            if url.scheme or url.netloc or url.fragment or '%' in url.path or not url.path.isascii():
                return False
            if url.query and any('=' not in part for part in url.query.split('&')):
                return False
            items = parse_qsl(url.query, keep_blank_values=True)
            if len(dict(items)) != len(items):
                return False
            query = dict(items)
            suffix = url.path[len(BASE)+1:] if url.path.startswith(BASE + '/') else ''
            identifier = suffix if re.fullmatch(r'91(?:0[1-9]|[12][0-9]|3[0-3])', suffix) else None
            if method == 'DELETE':
                return identifier in ('9102', '9133') and not query and body is None
            if method == 'PATCH':
                if identifier != '9101' or query or not isinstance(body, dict) or not body or not set(body) <= {'name', 'vulnclass', 'severity', 'status'}:
                    return False
                if any(type(v) is not str or len(v.encode()) > 8192 for v in body.values()) or len(json.dumps(body).encode()) > 65536:
                    return False
                return ('severity' not in body or body['severity'] in LEVELS) and ('status' not in body or body['status'] in STATUSES)
            if method != 'GET' or body is not None:
                return False
            if url.path == BASE + '/stats':
                return not query
            if identifier:
                return set(query) <= {'context_task'} and ('context_task' not in query or query['context_task'] in TASKS)
            if url.path not in (BASE, BASE + '/groups', BASE + '/asset-tree'):
                return False
            if 'task' in query:
                return url.path == BASE and len(query) == 1 and query['task'] in TASKS
            if not set(query) <= {'page', 'limit', 'severity', 'status', 'vulnclass', 'task_id', 'q', 'sort', 'asset_scope'}:
                return False
            if any(len(v.encode()) > 8192 for v in query.values()):
                return False
            if 'page' in query or 'limit' in query:
                if url.path.endswith('/asset-tree') or query.get('page') not in ('1', '2', '3', '4') or query.get('limit') not in ('10', '20', '100'):
                    return False
            return (('severity' not in query or query['severity'] in LEVELS)
                    and ('status' not in query or query['status'] in STATUSES)
                    and ('task_id' not in query or query['task_id'] in TASKS + ('__unassigned__',))
                    and ('sort' not in query or query['sort'] in ('severity', 'time'))
                    and ('asset_scope' not in query or query['asset_scope'] in SCOPES))
        except (ValueError, TypeError, UnicodeError):
            return False


def dataset(persisted):
    rows = copy.deepcopy(list(seed.ROWS))
    if persisted:
        rows[0].update(name=EDITED_NAME, vulnclass=EDITED_CLASS, severity='low', status='fixed')
        rows = [r for r in rows if r['id'] not in (9102, 9133)]
    return rows


def scoped(row, scope):
    ids = row['asset_ids']
    if scope == '__none__': return not ids
    if scope == 'c:8200': return bool(ids)
    if scope == 'a:8201': return bool(set(ids) & {8201, 8202})
    return scope in ('a:8202', 'a:8203') and int(scope[2:]) in ids


def match(rows, query):
    found = []
    for row in rows:
        if any(query.get(k) and row[k] != query[k] for k in ('severity', 'status', 'vulnclass')): continue
        task = query.get('task_id')
        if task and (row['task_id'] is not None if task == '__unassigned__' else str(row['task_id']) != task): continue
        if query.get('asset_scope') and not scoped(row, query['asset_scope']): continue
        term = query.get('q', '').strip(JS_SPACE).encode().lower()
        if term and not any(term in row[k].encode().lower() for k in ('name', 'vulnclass', 'summary', 'evidence', 'report')): continue
        found.append(row)
    return sorted(found, key=lambda r: ((LEVELS.index(r['severity']) if query.get('sort', 'severity') == 'severity' else 0), -r['id']))


def vectors():
    def q(**values): return dict(page=1, limit=100, sort='severity', **values)
    cases = [('flat_severity_1', dict(page=1, limit=20, sort='severity')), ('flat_severity_2', dict(page=2, limit=20, sort='severity')),
             ('flat_out_of_range', dict(page=3, limit=20, sort='severity')), ('flat_time', dict(page=1, limit=100, sort='time'))]
    cases += [('severity_' + s, q(severity=s)) for s in LEVELS]
    cases += [('status_' + s, q(status=s)) for s in STATUSES]
    cases += [('class_' + str(i), q(vulnclass=c)) for i, c in enumerate(seed.CLASSES)]
    cases += [('task_' + t, q(task_id=t)) for t in TASKS + ('__unassigned__',)]
    cases += [('search_' + n, q(q=v)) for n, v in [('literal', seed.LITERAL), ('report', 'F4 report 33'), ('absent', 'F4 missing phrase'), ('escaped', '%_\\'), ('NFC_absent', 'F4 é')]]
    cases += [('asset_' + str(i), q(asset_scope=s)) for i, s in enumerate(SCOPES)]
    cases.append(('combined', q(severity='high', status='in_progress', vulnclass='CWE-89', task_id='8101', q="'quoted'", asset_scope='a:8201')))
    return cases


def path(route, query):
    values = dict(query)
    if 'q' in values: values['q'] = values['q'].strip(JS_SPACE)
    return route + '?' + urlencode(values)


def text(actual, expected):
    require(type(actual) is str and actual.encode() == expected.encode(), 'raw text')


def number(actual, expected):
    require(type(actual) is int and actual == expected, 'numeric value')


def identity(actual, expected):
    if expected is None:
        require(actual is None, 'optional identity')
    else:
        require(type(actual) in (str, int) and str(actual) == str(expected), 'identity')


def verify_row(actual, expected, *, report=True, node=False, inherited=False, legacy=False):
    require(isinstance(actual, dict), 'finding shape')
    text(actual.get('id'), str(expected['node_id'] if node else expected['id']))
    require(actual.get('finding_id') == (None if legacy else str(expected['id'])), 'standalone handle')
    require(actual.get('task_id') == (str(expected['task_id']) if expected['task_id'] else None), 'task owner')
    require(actual.get('source_task_id') == (str(expected['task_id']) if inherited else None) and actual.get('inherited', False) is inherited, 'provenance')
    for key in ('intent_id', 'param_id'): require(actual.get(key) is None, 'unexpected lineage')
    for key in ('traffic_count', 'evidence_version', 'report_evidence_version'): number(actual.get(key, 0), 0)
    require(actual.get('report_stale', False) is False, 'report stale')
    for key in ('name', 'vulnclass', 'severity', 'status', 'summary', 'ts'): text(actual.get(key), expected[key])
    description = f"F4 terminal task {expected['task_id']} {seed.LITERAL}" if expected['task_id'] else ''
    text(actual.get('task_description', ''), description)
    evidence = actual.get('evidence')
    if node:
        try: evidence = json.loads(evidence)
        except (ValueError, TypeError): raise RuntimeError('Findings reference node evidence') from None
    text(evidence, expected['evidence']); text(actual.get('report', ''), expected['report'] if report else '')
    assets = actual.get('assets')
    if assets is None: assets = []
    require(isinstance(assets, list) and len(assets) == len(expected['asset_ids']), 'assets')
    for value, aid in zip(assets, expected['asset_ids']):
        require(value.get('id') == str(aid) and value.get('type') == ASSETS[aid][0], 'asset identity/type')
        text(value.get('label'), ASSETS[aid][1])


def verify_page(actual, query, rows):
    found = match(rows, query); page, limit = query['page'], query['limit']
    expected = found[(page-1)*limit:page*limit]
    for key, value in [('total', len(found)), ('page', page), ('page_size', limit)]: number(actual.get(key), value)
    require([r.get('id') for r in actual['items']] == [str(r['id']) for r in expected], 'page order')
    for a, e in zip(actual['items'], expected): verify_row(a, e, report=False)


def severity_counts(actual, rows):
    for level in LEVELS: number(actual.get(level), sum(r['severity'] == level for r in rows))


def grouped(rows, sort):
    ids = {r['task_id'] for r in rows}
    groups = [(t, [r for r in rows if r['task_id'] == t]) for t in ids]
    return sorted(groups, key=lambda g: ((min(LEVELS.index(r['severity']) for r in g[1]) if sort == 'severity' else 0), -max(r['id'] for r in g[1])))


def task_text(actual, task, *, option=False):
    prefix = '' if option else 'task_'
    text(actual.get(prefix + 'name', ''), f'F4 task {task} {seed.LITERAL}' if task else '')
    text(actual.get(prefix + 'description', ''), f'F4 terminal task {task} {seed.LITERAL}' if task else '')


def verify_stats(actual, rows):
    number(actual.get('total'), len(rows)); number(actual.get('pending'), sum(r['status'] == 'pending' for r in rows)); severity_counts(actual, rows)
    require(actual.get('vulnclasses') == sorted({r['vulnclass'] for r in rows}), 'class options')
    tasks = [(t, r) for t, r in grouped(rows, 'time') if t is not None]
    require(len(actual['tasks']) == len(tasks), 'task option count')
    for value, (task, found) in zip(actual['tasks'], tasks):
        identity(value.get('id'), task); number(value.get('count'), len(found)); task_text(value, task, option=True)


def verify_groups(actual, query, rows):
    found = match(rows, query); groups = grouped(found, query['sort']); page, limit = query['page'], query['limit']
    for key, value in [('total', len(groups)), ('finding_total', len(found)), ('page', page), ('page_size', limit)]: number(actual.get(key), value)
    expected = groups[(page-1)*limit:page*limit]; require(len(actual['items']) == len(expected), 'group page length')
    for value, (task, items) in zip(actual['items'], expected):
        identity(value.get('task_id'), task); task_text(value, task)
        text(value.get('task_status'), 'done' if task else ''); number(value.get('count'), len(items)); severity_counts(value, items)
        text(value.get('last_found_at'), max(r['ts'] for r in items))


def verify_tree(actual, rows):
    number(actual.get('finding_total'), len(rows))
    dropped = actual.get('dropped_kinds')
    require(actual.get('truncated') is False and (dropped is None or (type(dropped) is list and not dropped)), 'tree truncation')
    metadata = [('c:8200', None, 'company', 'F4 company ' + seed.LITERAL, None, 8200),
                ('a:8201', 'c:8200', 'root_domain', 'fixture.example.test', 8201, 8200),
                ('a:8202', 'a:8201', 'subdomain', 'api.fixture.example.test', 8202, 8200),
                ('a:8203', 'c:8200', 'ip', '198.51.100.9', 8203, 8200), ('__none__', None, 'none', '未关联资产', None, None)]
    expected = [(meta, [r for r in rows if scoped(r, meta[0])]) for meta in metadata]
    expected = [(m, r) for m, r in expected if r]
    expected.sort(key=lambda item: (item[0][2] == 'none', -len(item[1]), item[0][3]))
    require([v.get('key') for v in actual['nodes']] == [m[0] for m, _ in expected], 'tree order')
    for value, ((key, parent, kind, label, asset, company), found) in zip(actual['nodes'], expected):
        require(value.get('parent') == parent and value.get('kind') == kind, 'tree hierarchy')
        text(value.get('label'), label)
        for field, wanted in [('asset_id', asset), ('company_id', company)]:
            if wanted is None: require(value.get(field) is None, 'tree absent identity')
            else: number(value.get(field), wanted)
        direct = sum(asset in r['asset_ids'] for r in rows) if asset else (len(found) if kind == 'none' else 0)
        number(value.get('self'), direct); number(value.get('total'), len(found)); severity_counts(value, found)
        text(value.get('last_found_at'), max(r['ts'] for r in found))


def verify_task(actual, task, rows):
    own = sorted([r for r in rows if str(r['task_id']) == task and r['node_id']], key=lambda r: -r['node_id'])
    source = sorted([r for r in rows if r['task_id'] == 8101], key=lambda r: -r['node_id']) if task == '8111' else []
    expected = [(r, False, False) for r in own] + [(r, True, False) for r in source]
    if task == '8111':
        legacy = dict(id=None, node_id=15190, task_id=8111, name='F4 legacy ' + seed.LITERAL, vulnclass='CWE-79', severity='low', status='pending',
                      summary='Legacy without standalone handle', evidence=seed.LITERAL, report='', asset_ids=[], ts='2026-10-22T10:00:59Z')
        expected.insert(0, (legacy, False, True))
    require(len(actual) == len(expected), 'task node count')
    for value, (row, inherited, legacy) in zip(actual, expected): verify_row(value, row, report=False, node=True, inherited=inherited, legacy=legacy)


def read_check_names(persisted):
    names = [name for name, _ in vectors()] + ['detail_' + str(r['id']) for r in dataset(persisted)] + ['stats']
    names += [f'groups_{sort}_{page}' for sort in ('severity', 'time') for page in range(1, 4 if sort == 'severity' else 3)]
    names += [f'expanded_8101_{p}' for p in (1, 2, 3)] + ['asset_tree'] + ['nodes_' + t for t in TASKS]
    names += ['context_8101', 'context_8111', 'unrelated_context_rejected']
    return names + (['deleted_9102', 'deleted_9133'] if persisted else [])


def read_snapshot(client, persisted):
    rows = dataset(persisted); checks = []
    for name, query in vectors():
        verify_page(client.api('GET', path(BASE, query)), query, rows); checks.append(name)
    for row in rows:
        verify_row(client.api('GET', BASE + '/' + str(row['id'])), row); checks.append('detail_' + str(row['id']))
    verify_stats(client.api('GET', BASE + '/stats'), rows); checks.append('stats')
    for sort in ('severity', 'time'):
        for page in range(1, 4 if sort == 'severity' else 3):
            query = dict(page=page, limit=10, sort=sort)
            verify_groups(client.api('GET', path(BASE + '/groups', query)), query, rows); checks.append(f'groups_{sort}_{page}')
    for page in (1, 2, 3):
        query = dict(page=page, limit=20, sort='severity', task_id='8101')
        verify_page(client.api('GET', path(BASE, query)), query, rows); checks.append(f'expanded_8101_{page}')
    verify_tree(client.api('GET', BASE + '/asset-tree?sort=severity'), rows); checks.append('asset_tree')
    for task in TASKS:
        verify_task(client.api('GET', BASE + '?task=' + task), task, rows); checks.append('nodes_' + task)
    for context in ('8101', '8111'):
        verify_row(client.api('GET', BASE + '/9101?context_task=' + context), rows[0], inherited=context == '8111'); checks.append('context_' + context)
    client.api('GET', BASE + '/9101?context_task=8102', expected=404); checks.append('unrelated_context_rejected')
    if persisted:
        for identifier in ('9102', '9133'):
            client.api('GET', BASE + '/' + identifier, expected=404); checks.append('deleted_' + identifier)
    require(checks == read_check_names(persisted), 'read coverage')
    return checks


def mutations(client):
    query = vectors()[0][1]; verify_page(client.api('GET', path(BASE, query)), query, dataset(False))
    expected = copy.deepcopy(dataset(False)[0]); verify_row(client.api('GET', BASE + '/9101'), expected)
    patch = dict(name=EDITED_NAME, vulnclass=EDITED_CLASS, severity='low'); expected.update(patch)
    verify_row(client.api('PATCH', BASE + '/9101', patch), expected)
    expected['status'] = 'confirmed'; verify_row(client.api('PATCH', BASE + '/9101', dict(status='confirmed')), expected)
    client.api('PATCH', BASE + '/9101', dict(name=NUL_NAME, status='risk_accepted'), expected=500)
    expected['status'] = 'risk_accepted'
    # Repeated reads witness the persisted partial state, without pretending to exercise browser UI uncertainty controls.
    for _ in range(2): verify_row(client.api('GET', BASE + '/9101'), expected)
    expected['status'] = 'fixed'; verify_row(client.api('PATCH', BASE + '/9101', dict(status='fixed')), expected)
    for identifier in (9102, 9133):
        row = next(r for r in dataset(False) if r['id'] == identifier)
        verify_row(client.api('GET', BASE + '/' + str(identifier)), row)
        receipt = client.api('DELETE', BASE + '/' + str(identifier))
        require(receipt.get('deleted') is True, 'delete receipt'); number(receipt.get('id'), identifier)
        client.api('GET', BASE + '/' + str(identifier), expected=404)
    return list(SHARED_MUTATIONS)


def boundaries(client):
    original = copy.deepcopy(dataset(False)[0]); expected = copy.deepcopy(original)
    verify_row(client.api('GET', BASE + '/9101'), expected)
    name = 'F4 boundary \ufeffe\u0301 中文 한국어'
    classification = 'F4 boundary class e\u0301 \ufeff interior 中文 한국어'
    long_class = '界' * 2730 + 'AB'
    require(len(long_class.encode('utf-8')) == 8192, 'diagnostic field bytes')
    # Match the frozen browser trim before dispatch; expected server results remain explicit.
    attempts = [
        (dict(name=('\ufeff \u0085 ' + name + ' \u0085 \ufeff').strip(JS_SPACE)), dict(name=name)),
        (dict(vulnclass=('\u0085 ' + classification + ' \u0085').strip(JS_SPACE)), dict(vulnclass=classification)),
        (dict(severity='medium'), dict(severity='medium')),
        (dict(name='\ufeff \t'.strip(JS_SPACE)), dict(name='')),
        (dict(vulnclass=long_class), dict(vulnclass=long_class)),
        ({key: original[key] for key in ('name', 'vulnclass', 'severity')},
         {key: original[key] for key in ('name', 'vulnclass', 'severity')})]
    for patch, changes in attempts:
        expected.update(changes)
        verify_row(client.api('PATCH', BASE + '/9101', patch), expected)
    return dict(boundaryChecks=list(BOUNDARY_SHARED), boundaryRequestCount=7, diagnosticFieldBytes=8192)


def before_restart(client):
    client.audit(); initial = read_snapshot(client, False); client.audit()
    boundary = boundaries(client); client.audit(); checks = mutations(client)
    verify_stats(client.api('GET', BASE + '/stats'), dataset(True)); verify_tree(client.api('GET', BASE + '/asset-tree?sort=severity'), dataset(True))
    client.audit(); require(client.calls == 123, 'before request count')
    return dict(initialChecks=initial, mutationChecks=checks, partialHTTPStatus=500, beforeRequestCount=client.calls, **boundary)


def sha256_file(path, *, maximum=128 * 1024 * 1024):
    digest = hashlib.sha256(); total = 0
    with path.open('rb') as stream:
        while True:
            block = stream.read(min(65536, maximum-total+1))
            if not block: break
            total += len(block); require(total <= maximum, 'source file bound'); digest.update(block)
    return digest.hexdigest()


def inspect_network():
    proof = check_network.inspect()
    require(check_network.is_isolated(proof), 'network hardware/active links/routes')
    return proof


def main():
    require(platform.system() == 'Linux' and platform.machine() == 'aarch64' and os.getuid() == 1000
            and os.environ.get('ARTEX_DISPOSABLE_REFERENCE') == '1', 'isolation')
    environment = seed.validate_environment()
    network = inspect_network()
    require(not DATA_ROOT.is_symlink() and not any(DATA_ROOT.iterdir()), 'fresh data directory')
    client = Client(); process = None; logs = []; tokens = [environment['PGPASSWORD']]
    checkpoint = result = None; before_audits = []; after_audits = []; seed_audits = []; stopped = 0
    try:
        for index in (1, 2, 3):
            child = dict(os.environ, ARTEX_SETUP_TOKEN=secrets.token_hex(32), ARTEX_LANG='en', ARTEX_SKILL_DIR='/opt/artex/skills')
            tokens.append(child['ARTEX_SETUP_TOKEN'])
            log = DATA_ROOT.parent / f'findings-reference-{index}.log'; logs.append(log)
            with log.open('xb') as stream:
                process = subprocess.Popen(['/opt/artex/artex', '-addr', '127.0.0.1:8787', '-data', str(DATA_ROOT), '-proxy', ''],
                                           cwd=DATA_ROOT, env=child, stdout=stream, stderr=subprocess.STDOUT)
            for _ in range(120):
                require(process.poll() is None, 'backend died')
                try:
                    status, auth = Client().request('GET', '/api/auth/status')
                    if status == 200: break
                except (OSError, ValueError): pass
                time.sleep(.25)
            else: raise RuntimeError('Findings reference readiness exhausted')
            require(Client().request('GET', '/api/llm/profiles')[0] == 401, 'protected API')
            if index == 1:
                require(auth.get('initialized') is False and auth.get('setup_token_required') is True, 'fresh authentication')
                password = secrets.token_hex(32); tokens.append(password)
                client.token = client.api('POST', '/api/auth/init', dict(password=password, setup_token=child['ARTEX_SETUP_TOKEN']))['token']; tokens.append(client.token)
                seed_audits.append(control.audit(fresh=True))
                with contextlib.redirect_stdout(io.StringIO()): seed.main()
                seed_audits.append(control.audit())
            else:
                require(auth.get('initialized') is True, 'persisted authentication'); client.api('GET', '/api/llm/profiles')
                bounded = Bounded(client)
                if index == 2:
                    checkpoint = before_restart(bounded); before_audits = bounded.audits
                else:
                    bounded.audit(); checks = read_snapshot(bounded, True); bounded.audit()
                    require(bounded.calls == 100, 'after request count'); after_audits = bounded.audits
                    result = dict(checkpoint, finalChecks=checks, afterRequestCount=bounded.calls, passed=True)
            process.terminate(); code = process.wait(timeout=20); process = None
            require(code == 0, 'cooperative stop'); stopped += 1
        require(result is not None and stopped == 3, 'complete experiment')
        for log in logs:
            with log.open('rb') as stream: data = stream.read(4 * 1024 * 1024 + 1)
            require(len(data) <= 4 * 1024 * 1024 and all(t.encode() not in data for t in tokens), 'credential log audit')
        folder = Path(__file__).resolve().parent
        output = dict(comparison=result, backend_starts=3, cooperative_stops=stopped, fresh_setup=True, persisted_session=True,
                      protected_statuses=[401, 401, 401], credentials_absent=True, network_proof=network, networkCheckerSHA256=sha256_file(Path(check_network.__file__)), sourceCommit=SOURCE_COMMIT,
                      backendSHA256=sha256_file(Path('/opt/artex/artex')),
                      seedSHA256=sha256_file(folder/'findings_seed_guest.py'),
                      controlSHA256=sha256_file(folder/'findings_fixture_control.py'),
                      audit_proofs=dict(seed=seed_audits, before=before_audits, after=after_audits))
        print(json.dumps(output, ensure_ascii=False))
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)


if __name__ == '__main__':
    main()
