"""Fixed persisted history fixture for a private Linux reference or diagnostic VM."""
import json
import os
from pathlib import Path
import platform
import re
import subprocess
from urllib.parse import urlsplit

SQL = """
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '10s';
CREATE TABLE IF NOT EXISTS server_logs (
 id BIGSERIAL PRIMARY KEY,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 level TEXT NOT NULL DEFAULT 'info',
 tag TEXT NOT NULL DEFAULT '',
 text TEXT NOT NULL DEFAULT ''
);
LOCK TABLE server_logs IN EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM server_logs WHERE id >= 1000000 OR tag = 'history-review')
 OR (SELECT count(*) FROM server_logs) > 100
 THEN RAISE EXCEPTION 'fresh log history fixture required'; END IF;
END; $$;
INSERT INTO server_logs(id, created_at, level, tag, text)
 SELECT 1000000 + i, '2026-11-25 01:00:00+00'::timestamptz + i * interval '1 second',
        CASE i % 3 WHEN 0 THEN 'warn' WHEN 1 THEN 'info' ELSE 'error' END,
        'history-review', '[history-review] Log history fixture ' || lpad(i::text, 3, '0')
 FROM generate_series(1, 350) AS i;
ALTER SEQUENCE server_logs_id_seq RESTART WITH 1000351;
COMMIT;
"""


def environment():
    if (platform.system(), platform.machine(), os.getuid()) != ('Linux', 'aarch64', 1000):
        raise RuntimeError('Log fixture requires Linux/aarch64/UID1000')
    if os.environ.get('NETWORKPNTR_LOG_HISTORY_FIXTURE') != '1':
        raise RuntimeError('Explicit log history fixture mode required')
    for device in Path('/sys/class/net').iterdir():
        if device.is_dir() and device.name != 'lo' and int((device / 'flags').read_text().strip(), 16) & 1:
            raise RuntimeError('Log history fixture requires an isolated network')
    parsed = urlsplit(os.environ.get('ARTEX_PG_DSN', ''))
    if (parsed.scheme, parsed.hostname, parsed.port, parsed.username, parsed.path, parsed.query, parsed.fragment) != (
        'postgres', '127.0.0.1', 5432, 'artex', '/artex', 'sslmode=disable', ''
    ) or not re.fullmatch('[0-9a-f]{64}', parsed.password or ''):
        raise RuntimeError('Log history fixture requires the exact private loopback database')
    return {'PGHOST': '127.0.0.1', 'PGPORT': '5432', 'PGDATABASE': 'artex', 'PGUSER': 'artex',
            'PGPASSWORD': parsed.password, 'PGCONNECT_TIMEOUT': '2', 'PGCLIENTENCODING': 'UTF8'}


def main():
    settings = environment()
    try:
        subprocess.run(['/usr/libexec/postgresql16/psql', '-X', '-q', '-w', '-v', 'ON_ERROR_STOP=1'],
                       env=settings, input=SQL.encode(), stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        raise RuntimeError('Log history fixture transaction failed') from None
    print(json.dumps({'log_fixture_seeded': True, 'rows': 350}))


if __name__ == '__main__':
    main()
