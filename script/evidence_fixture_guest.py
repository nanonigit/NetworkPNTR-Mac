"""Fixed diagnostic evidence only. No CLI inputs; never a product endpoint."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import subprocess

ROOT = Path('/state/app/data/evidence')
CHUNK = bytes(range(256)) * 256
LITERAL = '\ufeffe\u0301 English Japanese \u65e5\u672c\u8a9e \u4e2d\u6587 \ud55c\uad6d\uc5b4\r\n'.encode()
SIZES = {'literal': len(LITERAL), 'binary': 5 * 1024 * 1024 + 17, 'empty': 0, 'large': 129 * 1024 * 1024 + 17}


def body_chunks(name):
    if name not in SIZES:
        raise RuntimeError('Unknown fixed evidence body')
    if name == 'literal':
        yield LITERAL
        return
    remaining = SIZES[name]
    while remaining:
        chunk = CHUNK[:min(remaining, len(CHUNK))]
        yield chunk
        remaining -= len(chunk)


def body_manifest():
    result = {}
    for name, size in SIZES.items():
        digest = hashlib.sha256()
        for chunk in body_chunks(name):
            digest.update(chunk)
        result[name] = {'size': size, 'sha256': digest.hexdigest()}
    return result


def _directory(path):
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError('Evidence fixture directory ownership failed')


def _path(row):
    return ROOT / 'blobs' / row['sha256'][:2] / (row['sha256'] + '.bin')


def write_bodies():
    created = []
    incomplete = False
    try:
        _directory(ROOT)
        _directory(ROOT / 'blobs')
        manifest = body_manifest()
        for name, row in manifest.items():
            path = _path(row)
            _directory(path.parent)
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
            try:
                info = os.fstat(fd)
                created.append((path, info.st_dev, info.st_ino))
            except OSError:
                os.close(fd)
                incomplete = True
                raise
            with os.fdopen(fd, 'wb') as output:
                for chunk in body_chunks(name):
                    if output.write(chunk) != len(chunk):
                        raise RuntimeError('Evidence fixture short write')
                output.flush()
                os.fsync(output.fileno())
        audit_bodies()
        return manifest
    except (OSError, RuntimeError):
        # Only files exclusively created by this invocation are eligible for cleanup.
        for path, device, inode in reversed(created):
            try:
                info = path.lstat()
                if stat.S_ISREG(info.st_mode) and (info.st_dev, info.st_ino) == (device, inode):
                    path.unlink()
                else:
                    incomplete = True
            except FileNotFoundError:
                continue
            except OSError:
                incomplete = True
        if incomplete:
            raise RuntimeError('Evidence fixture body creation failed; cleanup incomplete') from None
        raise RuntimeError('Evidence fixture body creation failed') from None


def audit_bodies():
    try:
        for path in (ROOT, ROOT / 'blobs'):
            info = path.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
                raise RuntimeError('Evidence fixture directory audit failed')
        manifest = body_manifest()
        for row in manifest.values():
            path = _path(row)
            info = path.parent.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
                raise RuntimeError('Evidence fixture prefix audit failed')
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
            with os.fdopen(fd, 'rb') as stream:
                info = os.fstat(stream.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size != row['size']:
                    raise RuntimeError('Evidence fixture body metadata failed')
                digest, count = hashlib.sha256(), 0
                while True:
                    chunk = stream.read(65536)
                    if not chunk:
                        break
                    digest.update(chunk)
                    count += len(chunk)
                if count != row['size'] or digest.hexdigest() != row['sha256']:
                    raise RuntimeError('Evidence fixture body hash failed')
        return manifest
    except OSError:
        raise RuntimeError('Evidence fixture body audit failed') from None


def snapshots():
    bodies, rows = body_manifest(), []
    for index, (request, response) in enumerate((('literal', 'binary'), ('empty', 'large'))):
        # Match the frozen Go struct's field order, omitempty and zero time before hashing.
        row = {'id': '', 'source_traffic_id': ('f5-fixed-binary', 'f5-fixed-large')[index],
               'captured_at': 1792641600000 + index, 'url': 'https://evidence-fixture.invalid/' + response,
               'method': 'POST', 'status': 200, 'content_type': 'application/octet-stream',
               'req_head': 'POST /' + response + ' HTTP/1.1\r\nHost: evidence-fixture.invalid\r\n\r\n',
               'resp_head': 'HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n\r\n',
               'req_hash': bodies[request]['sha256'], 'resp_hash': bodies[response]['sha256'],
               'req_len': bodies[request]['size'], 'resp_len': bodies[response]['size'], 'created_at': '0001-01-01T00:00:00Z'}
        raw = json.dumps(row, ensure_ascii=False, separators=(',', ':')).encode()
        row['id'] = hashlib.sha256(raw).hexdigest()
        rows.append(row)
    return rows


def _quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def fixture_sql():
    sql = ["BEGIN;", "SET LOCAL lock_timeout = '2s';", "SET LOCAL statement_timeout = '5s';",
           'SET LOCAL standard_conforming_strings = on;',
           'LOCK TABLE findings,traffic_evidence_snapshots,finding_traffic_bindings IN EXCLUSIVE MODE;',
           "DO $$ BEGIN IF (SELECT count(*) FROM findings) <> 33 OR NOT EXISTS (SELECT 1 FROM findings WHERE id=9101) OR EXISTS (SELECT 1 FROM traffic_evidence_snapshots) OR EXISTS (SELECT 1 FROM finding_traffic_bindings) THEN RAISE EXCEPTION 'fresh evidence fixture required'; END IF; END; $$;"]
    for index, row in enumerate(snapshots()):
        columns = [key for key in row if key != 'created_at']
        sql.append('INSERT INTO traffic_evidence_snapshots(' + ','.join(columns) + ') VALUES (' + ','.join(_quote(row[key]) for key in columns) + ');')
        sql.append('INSERT INTO finding_traffic_bindings(id,finding_id,snapshot_id,role,note,position) VALUES (' + str(17001 + index) + ',9101,' + _quote(row['id']) + ",'supporting','F5 original bytes'," + str(index) + ');')
    sql += ['UPDATE findings SET evidence_version=1 WHERE id=9101;', 'ALTER SEQUENCE finding_traffic_bindings_id_seq RESTART WITH 17003;', 'COMMIT;']
    return '\n'.join(sql)


def guest_environment():
    from findings_seed_guest import validate_environment
    return validate_environment()


def run_sql(environment, sql, *, proof=False):
    try:
        response = subprocess.run(['psql', '-X', '--no-password', '-t', '-A', '-q', '-v', 'ON_ERROR_STOP=1'],
                                  input=sql.encode(), env=environment, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, timeout=20)
        if response.returncode != 0 or len(response.stdout) > 65536:
            raise RuntimeError('Evidence fixture database failed')
        if proof:
            value = json.loads(response.stdout)
            if not isinstance(value, dict):
                raise RuntimeError('Evidence fixture database proof failed')
            return value
    except (OSError, subprocess.SubprocessError, ValueError):
        raise RuntimeError('Evidence fixture database failed') from None


def audit():
    environment = guest_environment()
    import findings_fixture_control as control
    counts = control._query(environment)
    allowed = {'traffic_bindings': 2, 'traffic_snapshots': 2}
    if (set(counts) != set(control.ZERO_KEYS) | set(control.COUNT_QUERIES)
            or any(type(v) is not int or v < 0 for v in counts.values())
            or any(counts[k] != allowed.get(k, 0) for k in control.ZERO_KEYS)
            or [counts[k] for k in ('tasks', 'explorations', 'relations', 'companies', 'assets', 'findings', 'finding_nodes')] != [11, 11, 1, 1, 3, 33, 32]
            or counts['events'] > 3):
        raise RuntimeError('Evidence fixture activity audit failed')
    rows = snapshots()
    columns = ','.join(key for key in rows[0] if key != 'created_at')
    proof = run_sql(environment, "SET statement_timeout='5s'; SELECT json_build_object('snapshots',(SELECT json_agg(t ORDER BY source_traffic_id) FROM (SELECT " + columns + " FROM traffic_evidence_snapshots) t),'bindings',(SELECT json_agg(t ORDER BY id) FROM (SELECT id,finding_id,snapshot_id,role,note,position FROM finding_traffic_bindings) t));", proof=True)
    expected_rows = [{key: value for key, value in row.items() if key != 'created_at'} for row in rows]
    expected_bindings = [{'id': 17001 + index, 'finding_id': 9101, 'snapshot_id': row['id'], 'role': 'supporting', 'note': 'F5 original bytes', 'position': index} for index, row in enumerate(rows)]
    if proof != {'snapshots': expected_rows, 'bindings': expected_bindings}:
        raise RuntimeError('Evidence fixture stored metadata audit failed')
    return {'evidence_fixture': True, 'uid': os.getuid(), 'finding_id': 9101,
            'binding_ids': [17001, 17002], 'bodies': audit_bodies(), 'counts': counts}


def prepare():
    environment = guest_environment()
    import findings_seed_guest as seed
    import findings_fixture_control as control
    control.audit(fresh=True)
    with contextlib.redirect_stdout(io.StringIO()):
        seed.main()
    control.audit(fresh=False)
    write_bodies()
    # A database outcome may be unknown on timeout. Preserve diagnostic blobs, never retry or erase them.
    run_sql(environment, fixture_sql())
    return audit()
