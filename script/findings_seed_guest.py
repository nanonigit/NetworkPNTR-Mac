"""One-shot terminal findings data for a fresh diagnostic guest; never a product API."""
import json
import os
import platform
import re
import subprocess
from urllib.parse import parse_qsl, unquote, urlsplit

TASK_IDS = tuple(range(8101, 8112))
LEGACY_NODE_ID = 15190
LITERAL = "\ufeffe\u0301 中文 한국어 'quoted'"
GOAL = 'Synthetic terminal Findings fixture; no agent execution'
SEVERITIES = ('critical', 'high', 'medium', 'low')
STATUSES = ('pending', 'in_progress', 'confirmed', 'resolved', 'fixed', 'false_positive', 'ignored', 'duplicate', 'risk_accepted')
CLASSES = ('CWE-79', 'CWE-89', 'F4 e\u0301 中文 한국어')
ROWS = tuple({
    'id': 9101 + index,
    'task_id': 8101 if index < 21 else (8102 + index - 21 if index < 31 else None),
    'node_id': 15101 + index if index < 31 else None,
    'name': f'F4 finding {index + 1} {LITERAL}',
    'vulnclass': CLASSES[index % 3], 'severity': SEVERITIES[index % 4], 'status': STATUSES[index % 9],
    'summary': f'F4 summary {index + 1} {LITERAL}',
    'evidence': f'F4 literal evidence {index + 1} {LITERAL}',
    'report': f'# F4 report {index + 1}\n\n{LITERAL}',
    'asset_ids': [] if index % 5 == 0 else ([8201, 8202] if index % 5 == 1 else [8201 + index % 3]),
    'ts': f'2026-10-22T10:00:{index:02d}Z',
} for index in range(33))

# Only these trusted constants become SQL. No environment, arguments or API input is interpolated.
EMPTY_TABLES = ('tasks', 'explorations', 'exploration_nodes', 'findings', 'companies', 'assets',
                'task_relations', 'task_categories', 'task_archives', 'task_asset_links',
                'llm_profiles', 'llm_records', 'llm_usage', 'activity', 'conversations',
                'intercept_pending', 'finding_retests', 'finding_traffic_bindings')


def _quote(value):
    return "'" + value.replace("'", "''") + "'"


def _json(value):
    return _quote(json.dumps(value, ensure_ascii=False, separators=(',', ':'))) + '::jsonb'


def _sql():
    sql = ["BEGIN;", "SET LOCAL lock_timeout = '2s';", "SET LOCAL statement_timeout = '5s';",
           'SET LOCAL standard_conforming_strings = on;',
           'LOCK TABLE ' + ','.join(EMPTY_TABLES) + ' IN EXCLUSIVE MODE;',
           'DO $$ BEGIN IF ' + ' OR '.join(f'EXISTS (SELECT 1 FROM {table})' for table in EMPTY_TABLES)
           + " THEN RAISE EXCEPTION 'fresh findings fixture required'; END IF; END; $$;"]
    for task in TASK_IDS:
        description = f'F4 terminal task {task} {LITERAL}'
        sql.append(f"INSERT INTO explorations(id,description,goal,status) VALUES ({task},{_quote(description)},{_quote(GOAL)},'achieved');")
        sql.append('INSERT INTO tasks(id,name,description,goal,exploration_id,status,paused,queued,'
                   'llm_profile_id,active_llm_profile_id,timeout_seconds,plan_heartbeat_seconds,completed_at) VALUES '
                   f"({task},{_quote(f'F4 task {task} {LITERAL}')},{_quote(description)},{_quote(GOAL)},"
                   f"{task},'done',false,false,NULL,NULL,0,0,'2026-10-22T09:00:00Z');")
    sql.append(f"INSERT INTO companies(id,name,nkey) VALUES (8200,{_quote('F4 company ' + LITERAL)},'f4 diagnostic company');")
    tasks = 'ARRAY[' + ','.join(str(task) for task in TASK_IDS) + ']::bigint[]'
    sql.append('INSERT INTO assets(id,type,company_id,task_ids,domain,root_domain,ip) VALUES '
               f"(8201,'root_domain',8200,{tasks},'fixture.example.test','fixture.example.test',NULL),"
               f"(8202,'subdomain',8200,{tasks},'api.fixture.example.test','fixture.example.test',NULL),"
               f"(8203,'ip',8200,{tasks},NULL,NULL,'198.51.100.9');")
    for row in ROWS:
        if row['node_id'] is not None:
            payload = {key: row[key] for key in ('name', 'vulnclass', 'severity', 'summary', 'evidence')}
            sql.append('INSERT INTO exploration_nodes(id,exploration_id,kind,payload,state,created_at,updated_at) VALUES '
                       f"({row['node_id']},{row['task_id']},'finding',{_json(payload)},'confirmed',{_quote(row['ts'])},{_quote(row['ts'])});")
        text = ','.join(_quote(row[key]) for key in ('name', 'vulnclass', 'severity', 'status', 'summary', 'evidence', 'report'))
        sql.append('INSERT INTO findings(id,task_id,node_id,name,vulnclass,severity,status,summary,evidence,report,asset_ids,created_at) VALUES '
                   f"({row['id']},{row['task_id'] if row['task_id'] is not None else 'NULL'},"
                   f"{row['node_id'] if row['node_id'] is not None else 'NULL'},{text},{_json(row['asset_ids'])},{_quote(row['ts'])});")
    legacy = {'name': 'F4 legacy ' + LITERAL, 'vulnclass': 'CWE-79', 'severity': 'low', 'summary': 'Legacy without standalone handle', 'evidence': LITERAL}
    sql.append('INSERT INTO exploration_nodes(id,exploration_id,kind,payload,state,created_at,updated_at) VALUES '
               f"({LEGACY_NODE_ID},8111,'finding',{_json(legacy)},'confirmed','2026-10-22T10:00:59Z','2026-10-22T10:00:59Z');")
    sql.append('INSERT INTO task_relations(task_id,source_task_id) VALUES (8111,8101);')
    for table, maximum in (('tasks', 8111), ('explorations', 8111), ('companies', 8200), ('assets', 8203), ('findings', 9133), ('exploration_nodes', LEGACY_NODE_ID)):
        # RESTART is transactional; setval would survive a later rollback.
        sql.append(f'ALTER SEQUENCE {table}_id_seq RESTART WITH {maximum + 1};')
    sql.append("""DO $$ BEGIN
 IF (SELECT count(*) FROM findings) <> 33 OR (SELECT count(*) FROM tasks) <> 11
 OR (SELECT count(*) FROM explorations) <> 11 OR (SELECT count(*) FROM exploration_nodes) <> 32
 OR (SELECT count(*) FROM companies) <> 1 OR (SELECT count(*) FROM assets) <> 3
 OR (SELECT count(*) FROM task_relations) <> 1
 OR EXISTS (SELECT 1 FROM tasks WHERE status <> 'done' OR paused OR queued
    OR llm_profile_id IS NOT NULL OR active_llm_profile_id IS NOT NULL
    OR timeout_seconds <> 0 OR plan_heartbeat_seconds <> 0)
 THEN RAISE EXCEPTION 'findings fixture postcondition'; END IF;
END; $$;
COMMIT;""")
    return '\n'.join(sql)


SQL = _sql()


def validate_environment():
    if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.getuid() != 1000:
        raise RuntimeError('Findings fixture requires diagnostic Linux/aarch64/UID1000')
    if os.environ.get('ARTEX_FINDINGS_FIXTURE') != '1':
        raise RuntimeError('Findings fixture requires explicit diagnostic mode')
    try:
        parsed = urlsplit(os.environ.get('ARTEX_PG_DSN', ''))
        password = unquote(parsed.password or '')
        valid = (parsed.scheme in ('postgres', 'postgresql') and parsed.hostname == '127.0.0.1'
                 and parsed.port == 5432 and unquote(parsed.username or '') == 'artex'
                 and parsed.path == '/artex' and not parsed.fragment
                 and parse_qsl(parsed.query, keep_blank_values=True) == [('sslmode', 'disable')]
                 and re.fullmatch('[0-9a-f]{64}', password) is not None)
    except ValueError:
        valid = False
    if not valid:
        raise RuntimeError('Findings fixture requires the exact guest loopback database')
    return {'PATH': '/usr/libexec/postgresql16:/usr/bin:/bin', 'PGHOST': '127.0.0.1',
            'PGPORT': '5432', 'PGDATABASE': 'artex', 'PGUSER': 'artex', 'PGPASSWORD': password,
            'PGCONNECT_TIMEOUT': '2', 'PGCLIENTENCODING': 'UTF8'}


def main():
    environment = validate_environment()
    try:
        result = subprocess.run(['psql', '-X', '--no-password', '-q', '-v', 'ON_ERROR_STOP=1'],
                                input=SQL.encode(), env=environment, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=15)
    except (OSError, subprocess.SubprocessError):
        raise RuntimeError('Findings fixture database phase failed') from None
    if result.returncode != 0:
        raise RuntimeError('Findings fixture transaction failed')
    print(json.dumps({'fixture_seeded': True, 'task_ids': TASK_IDS,
                      'finding_ids': [row['id'] for row in ROWS], 'legacy_node_id': LEGACY_NODE_ID,
                      'asset_ids': [8201, 8202, 8203]}))


if __name__ == '__main__':
    main()
