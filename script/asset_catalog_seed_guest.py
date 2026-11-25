"""Fixed asset inventory for a fresh no-model diagnostic VM only."""
import json
import os
import platform
import re
import subprocess
from urllib.parse import parse_qsl, unquote, urlsplit

SQL = r"""
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '10s';
LOCK TABLE assets, tasks, llm_profiles, conversations IN EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM assets) OR EXISTS (SELECT 1 FROM tasks)
 OR EXISTS (SELECT 1 FROM llm_profiles) OR EXISTS (SELECT 1 FROM conversations)
 THEN RAISE EXCEPTION 'fresh asset fixture required'; END IF;
END; $$;
INSERT INTO assets(type,domain,root_domain,last_seen)
 SELECT 'root_domain','fixture-'||i||'.example.test','fixture-'||i||'.example.test',
        '2026-10-22T10:00:00Z'::timestamptz FROM generate_series(1,26) i;
COMMIT;
"""



def validate_environment():
    if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.getuid() != 1000:
        raise RuntimeError('Asset fixture requires isolated Linux/aarch64/UID1000')
    if os.environ.get('NETWORKPNTR_ASSET_FIXTURE') != '1':
        raise RuntimeError('Asset fixture requires explicit diagnostic mode')
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
        raise RuntimeError('Asset fixture requires the exact guest loopback database')
    return {'PATH': '/usr/libexec/postgresql16:/usr/bin:/bin', 'PGHOST': '127.0.0.1',
            'PGPORT': '5432', 'PGDATABASE': 'artex', 'PGUSER': 'artex', 'PGPASSWORD': password,
            'PGCONNECT_TIMEOUT': '2', 'PGCLIENTENCODING': 'UTF8'}


def main():
    environment = validate_environment()
    try:
        result = subprocess.run(['/usr/libexec/postgresql16/psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1'],
                                input=SQL.encode(), env=environment, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=15)
    except (OSError, subprocess.SubprocessError):
        raise RuntimeError('Asset fixture transaction failed') from None
    if result.returncode != 0:
        raise RuntimeError('Asset fixture transaction failed')
    print(json.dumps({'asset_fixture_seeded': True, 'linux_guest': True, 'uid': os.getuid(), 'asset_count': 26}))


if __name__ == '__main__':
    main()
