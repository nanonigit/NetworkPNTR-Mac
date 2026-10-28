"""Fixed native diagnostic bridge; actual capture uses the shared loopback fixture."""
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import stat
import time

import captured_fixture_guest as fixture

INDEX = Path('/state/app/data/traffic/_index/index.sqlite')


class NativeIndex:
    """Read metadata only; no auth material, captured inserts, or arbitrary routes."""
    def api(self, method, path):
        fixture.environment()
        fixture.require(method == 'GET' and path == '/api/traffic?page=0&size=500', 'native fixed index read')
        fixture.require(not any(p.is_symlink() for p in (INDEX, *INDEX.parents)), 'native nonsymlink index')
        info = INDEX.stat()
        fixture.require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_size <= 32*1024*1024, 'native owned regular index')
        deadline = time.monotonic()+2
        connection = sqlite3.connect(INDEX.as_uri()+'?mode=ro', uri=True, timeout=1)
        try:
            connection.set_progress_handler(lambda: int(time.monotonic() >= deadline), 1000)
            connection.execute('PRAGMA query_only=ON')
            names = ['id','ts','host','method','url','status','content_type','resp_len']
            values = connection.execute('SELECT id,ts,host,method,url,status,content_type,resp_len FROM exchanges LIMIT 30').fetchall()
            fixture.require(len(values) <= 29, 'native fixed index bound')
            rows = [dict(zip(names, row)) for row in values]
            for row in rows: row['ts'] = str(row['ts'])
            return dict(enabled=False, count=len(rows), total=len(rows), page=0, size=500, exchanges=rows)
        finally:
            connection.close()


def proof(records, counts):
    fixture.require(len(records) == 29, 'native exact record count')
    manifest = json.dumps(fixture.exchange_manifest(), sort_keys=True, separators=(',', ':')).encode()
    return dict(captured_native_fixture=True, uid=os.getuid(), finding_id=9101, records=len(records),
                manifest_sha256=hashlib.sha256(manifest).hexdigest(), counts=counts)


def prepare():
    fixture.environment()
    client = NativeIndex()
    initial = client.api('GET', '/api/traffic?page=0&size=500')
    fixture.require(initial.get('total') == initial.get('count') == 0 and initial.get('exchanges') == [], 'native empty index before seed')
    result = fixture.prepare(client=client)
    return proof(result['records'], result['counts'])


def audit():
    fixture.environment()
    rows = fixture.read_records(NativeIndex())
    return proof(rows, fixture.audit_activity(1, 2))
