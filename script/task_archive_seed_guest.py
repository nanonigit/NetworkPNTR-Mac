"""One-shot fixed terminal data for a fresh diagnostic VM, never a production seed."""
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
from urllib.parse import parse_qsl, unquote, urlsplit

DATA_ROOT = Path('/state/app/data')
TASK_IDS = [7101, 7102]
NAME = '\ufeffe\u0301 中文 한국어'
DESCRIPTION = 'Archive fixture e\u0301 \ufeff interior 中文 한국어'
GOAL = 'Synthetic terminal archive fixture; no agent execution'
FILES = (
    ('tasks/7101/workspace/fixture-e\u0301.txt', 'Archive bytes \ufeff e\u0301 日本語\n'.encode()),
    ('tasks/7101/workspace/empty.bin', b''),
    ('tasks/7102/workspace/fixture.bin', bytes(range(256)) * 4),
)
# Only literal trusted fixture strings are interpolated, never environment or API inputs.
SQL = f"""
BEGIN;
LOCK TABLE tasks, explorations, task_archives, task_categories, llm_profiles,
 activity, findings, assets, conversations, llm_usage, intercept_pending IN EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM tasks) OR EXISTS (SELECT 1 FROM explorations)
 OR EXISTS (SELECT 1 FROM task_archives) OR EXISTS (SELECT 1 FROM task_categories)
 OR EXISTS (SELECT 1 FROM llm_profiles) OR EXISTS (SELECT 1 FROM activity)
 OR EXISTS (SELECT 1 FROM findings) OR EXISTS (SELECT 1 FROM assets)
 OR EXISTS (SELECT 1 FROM conversations) OR EXISTS (SELECT 1 FROM llm_usage)
 OR EXISTS (SELECT 1 FROM intercept_pending) OR EXISTS (SELECT 1 FROM task_relations)
 THEN RAISE EXCEPTION 'fresh archive fixture required'; END IF;
END; $$;
INSERT INTO task_categories(id,name) VALUES (7100,'T17 archive category');
INSERT INTO explorations(id,description,goal,status) VALUES
 (7101,$fixture${DESCRIPTION}$fixture$,$fixture${GOAL}$fixture$,'achieved'),
 (7102,'Archive fixture second',$fixture${GOAL}$fixture$,'achieved');
INSERT INTO tasks(id,name,category_id,description,goal,exploration_id,status,paused,queued,
 llm_profile_id,active_llm_profile_id,timeout_seconds,plan_heartbeat_seconds,completed_at) VALUES
 (7101,$fixture${NAME}$fixture$,7100,$fixture${DESCRIPTION}$fixture$,$fixture${GOAL}$fixture$,
  7101,'done',false,false,NULL,NULL,0,0,'2026-10-22T12:00:00Z'),
 (7102,'T17 second',7100,'Archive fixture second',$fixture${GOAL}$fixture$,
  7102,'done',false,false,NULL,NULL,0,0,'2026-10-22T12:00:00Z');
SELECT setval('explorations_id_seq',7102),setval('tasks_id_seq',7102),setval('task_categories_id_seq',7100);
COMMIT;
"""


def validate_environment():
    if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.getuid() != 1000:
        raise RuntimeError('Archive fixture requires isolated Linux/aarch64/UID1000')
    if os.environ.get('ARTEX_ARCHIVE_FIXTURE') != '1':
        raise RuntimeError('Archive fixture requires explicit diagnostic mode')
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
        raise RuntimeError('Archive fixture requires the exact guest loopback database')
    return {'PATH': '/usr/libexec/postgresql16:/usr/bin:/bin', 'PGHOST': '127.0.0.1',
            'PGPORT': '5432', 'PGDATABASE': 'artex', 'PGUSER': 'artex', 'PGPASSWORD': password,
            'PGCONNECT_TIMEOUT': '2', 'PGCLIENTENCODING': 'UTF8'}


def validate_paths(root):
    try:
        if root.is_symlink() or not root.is_dir() or root.resolve(strict=True) != root:
            raise RuntimeError('Archive fixture requires a canonical data directory')
        tasks = root / 'tasks'
        if tasks.is_symlink() or (tasks.exists() and (not tasks.is_dir() or any(tasks.iterdir()))):
            raise RuntimeError('Archive fixture refuses existing task files')
    except OSError as error:
        raise RuntimeError('Archive fixture path validation failed') from None


def write_files(root):
    validate_paths(root)
    tasks = root / 'tasks'
    tasks.mkdir(mode=0o700, exist_ok=True)
    proof = []
    try:
        for identifier in TASK_IDS:
            (tasks / str(identifier)).mkdir(mode=0o700)
            (tasks / str(identifier) / 'workspace').mkdir(mode=0o700)
        for name, data in FILES:
            with (root / name).open('xb') as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            proof.append({'path': name, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    except OSError:
        raise RuntimeError('Archive fixture exclusive file creation failed') from None
    return proof


def main():
    child_env = validate_environment()
    validate_paths(DATA_ROOT)
    try:
        result = subprocess.run(['psql', '-X', '--no-password', '-q', '-v', 'ON_ERROR_STOP=1'],
                                input=SQL.encode(), env=child_env, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=15)
    except (OSError, subprocess.SubprocessError):
        raise RuntimeError('Archive fixture database phase failed') from None
    if result.returncode != 0:
        raise RuntimeError('Archive fixture transaction failed')
    # SQL and files are not atomic. Any failure is retained on this disposable disk; never retry it.
    try:
        files = write_files(DATA_ROOT)
    except OSError:
        raise RuntimeError('Archive fixture filesystem phase failed') from None
    print(json.dumps({'fixture_seeded': True, 'terminal_task_ids': TASK_IDS, 'files': files}, ensure_ascii=False))


if __name__ == '__main__':
    main()
