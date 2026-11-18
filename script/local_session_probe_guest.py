"""Read-only fixture proof; executes only inside the private Linux guest."""
import hashlib
import json
import os
import platform
import re
import subprocess
from urllib.parse import parse_qsl, unquote, urlsplit


def probe():
    if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.getuid() != 1000:
        raise RuntimeError('Private guest fixture required')
    if os.environ.get('NETWORKPNTR_LOCAL_SESSION_CAPABILITY'):
        raise RuntimeError('Native capability inherited by tool')
    parsed = urlsplit(os.environ.get('ARTEX_PG_DSN', ''))
    password = unquote(parsed.password or '')
    if not (parsed.scheme == 'postgres' and parsed.hostname == '127.0.0.1' and parsed.port == 5432
            and parsed.username == 'artex' and parsed.path == '/artex' and not parsed.fragment
            and parse_qsl(parsed.query) == [('sslmode', 'disable')] and re.fullmatch('[0-9a-f]{64}', password)):
        raise RuntimeError('Exact guest database required')
    env = {'PATH': '/usr/libexec/postgresql16:/usr/bin:/bin', 'PGHOST': '127.0.0.1', 'PGPORT': '5432',
           'PGDATABASE': 'artex', 'PGUSER': 'artex', 'PGPASSWORD': password, 'PGCONNECT_TIMEOUT': '2'}
    sql = "SELECT json_build_object('hash',(SELECT value FROM settings WHERE key='auth.password_hash'),'profiles',(SELECT json_agg(json_build_array(id,api_key) ORDER BY id) FROM llm_profiles),'tasks',(SELECT count(*) FROM tasks),'usage',(SELECT count(*) FROM llm_usage));"
    response = subprocess.run(['psql', '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'], input=sql.encode(),
                              env=env, capture_output=True, timeout=5)
    if response.returncode != 0:
        raise RuntimeError('Guest fixture query failed')
    record = json.loads(response.stdout)
    if not record.get('hash') or record['usage'] != 0:
        raise RuntimeError('Unexpected fixture state')
    # Only digests and nonsensitive counts leave the guest; no hashes or API keys.
    fingerprint = hashlib.sha256(json.dumps(record, sort_keys=True).encode()).hexdigest()
    print(json.dumps({'fingerprint': fingerprint, 'capabilityNotInherited': True, 'usage': 0, 'tasks': record['tasks']}))


if __name__ == '__main__':
    probe()
