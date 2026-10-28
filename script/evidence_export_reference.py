"""Independent fixed-loopback evidence API reference; main runs only in an owned Linux guest."""
import contextlib
import hashlib
import http.client
import json
import os
from pathlib import Path
import platform
import re
import secrets
import stat
import subprocess
import time

import evidence_fixture_guest as fixture

SOURCE_COMMIT = 'e75ae371ad777ffd1eecdd28d2781a6519b05591'
BACKEND_SHA256 = '0ebad83ddda276b03b415d64ce30af44e7a587860f3b660c12563462a0ac5e80'
DATA_ROOT = Path('/state/app/data')
DOWNLOAD_ROOT = Path('/state/evidence-downloads')
BASE = '/api/exploration/findings/9101/traffic'
PAIRS = {'17001': {'request': 'literal', 'response': 'binary'}, '17002': {'request': 'empty', 'response': 'large'}}


def require(value, message):
    if not value:
        raise RuntimeError('Evidence reference ' + message)


def digest_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        while True:
            chunk = stream.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


class Client:
    def __init__(self, *, connection_factory=http.client.HTTPConnection, clock=time.monotonic):
        self.factory, self.clock = connection_factory, clock
        self.deadline, self.calls, self.token = clock() + 180, 0, None

    def check(self):
        require(self.clock() <= self.deadline and self.calls <= 256, 'request bound/deadline')

    def connection(self, method, path, body=None):
        self.check()
        require(self.calls < 256, 'request count exhausted')
        require(self.token is None or (isinstance(self.token, str) and re.fullmatch(r'[A-Za-z0-9_.~-]{1,8192}', self.token)), 'bearer shape')
        headers = {'Connection': 'close', 'Accept-Encoding': 'identity'}
        if self.token is not None:
            headers['Authorization'] = 'Bearer ' + self.token
        if body is not None:
            headers['Content-Type'] = 'application/json'
        connection = self.factory('127.0.0.1', 8787, timeout=30)
        self.calls += 1
        try:
            connection.request(method, path, body=body, headers=headers)
            return connection, connection.getresponse()
        except BaseException:
            connection.close()
            raise

    def api(self, method, path, body=None, *, expected=200):
        reads = {'/api/auth/status', '/api/llm/profiles', BASE}
        reads.update(BASE + '/' + binding + '/body?side=' + side + '&offset=0' for binding in PAIRS for side in PAIRS[binding])
        require((method == 'GET' and path in reads and body is None)
                or (method == 'POST' and path in ('/api/auth/init', '/api/auth/login') and isinstance(body, dict)), 'fixed JSON route')
        payload = None if body is None else json.dumps(body, allow_nan=False, separators=(',', ':')).encode()
        require(payload is None or len(payload) <= 8192, 'JSON request size')
        connection, response = self.connection(method, path, payload)
        try:
            require(response.status == expected, 'API status')
            result = bytearray()
            while True:
                self.check()
                chunk = response.read(65536)
                require(len(chunk) <= 65536 and len(result) + len(chunk) <= 4 * 1024 * 1024, 'JSON response size')
                if not chunk:
                    break
                result.extend(chunk)
            value = json.loads(result)
            require(isinstance(value, dict), 'JSON object')
            return value
        except (ValueError, OSError):
            raise RuntimeError('Evidence reference JSON failed') from None
        finally:
            connection.close()

    def download(self, boot, binding, side):
        require(type(boot) is int and boot in (1, 2) and binding in PAIRS and side in PAIRS[binding], 'fixed body route')
        name = PAIRS[binding][side]
        row = fixture.body_manifest()[name]
        path = BASE + '/' + binding + '/body?side=' + side + '&download=1'
        connection, response = self.connection('GET', path)
        output, owned, created = None, None, False
        try:
            require(response.status == 200, 'download status')
            headers = {}
            for key, value in response.getheaders():
                key = key.lower()
                require(key not in headers or key not in ('content-length', 'transfer-encoding', 'content-encoding'), 'duplicate framing')
                headers[key] = value
            require(headers.get('content-length') == str(row['size']) and 'transfer-encoding' not in headers
                    and headers.get('content-encoding', 'identity') == 'identity', 'identity framing')
            fixture._directory(DOWNLOAD_ROOT)
            folder = DOWNLOAD_ROOT / ('boot-' + str(boot)); fixture._directory(folder)
            output = folder / (name + '.bin')
            fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
            created = True
            source = fixture.ROOT / 'blobs' / row['sha256'][:2] / (row['sha256'] + '.bin')
            source_fd = None
            try:
                info = os.fstat(fd); owned = (info.st_dev, info.st_ino)
                source_fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
                info = os.fstat(source_fd)
                require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_size == row['size'], 'source regular body')
                digest, count = hashlib.sha256(), 0
                with contextlib.ExitStack() as stack:
                    saved = stack.enter_context(os.fdopen(fd, 'wb')); fd = None
                    original = stack.enter_context(os.fdopen(source_fd, 'rb')); source_fd = None
                    while True:
                        self.check()
                        chunk = response.read(65536)
                        require(len(chunk) <= 65536 and len(chunk) <= row['size'] - count, 'body size')
                        if not chunk:
                            break
                        require(original.read(len(chunk)) == chunk, 'full byte comparison')
                        require(saved.write(chunk) == len(chunk), 'saved write')
                        digest.update(chunk); count += len(chunk)
                    require(count == row['size'] and original.read(1) == b'' and digest.hexdigest() == row['sha256'], 'complete body hash')
                    saved.flush(); os.fsync(saved.fileno())
                return {'body': name, 'binding_id': binding, 'side': side, 'bytes': count, 'sha256': digest.hexdigest(), 'full_byte_equal': True}
            finally:
                if fd is not None:
                    os.close(fd)
                if source_fd is not None:
                    os.close(source_fd)
        except (OSError, RuntimeError):
            if created and owned is None:
                raise RuntimeError('Evidence reference download failed; cleanup incomplete') from None
            if owned is not None:
                try:
                    current = output.lstat()
                    require(stat.S_ISREG(current.st_mode) and (current.st_dev, current.st_ino) == owned, 'cleanup ownership')
                    output.unlink()
                except (OSError, RuntimeError):
                    raise RuntimeError('Evidence reference download failed; cleanup incomplete') from None
            raise RuntimeError('Evidence reference download failed') from None
        finally:
            connection.close()


def main():
    require(platform.system() == 'Linux' and platform.machine() == 'aarch64' and os.getuid() == 1000
            and os.environ.get('ARTEX_DISPOSABLE_REFERENCE') == '1', 'owned guest only')
    environment = fixture.guest_environment()
    import check_network
    network = check_network.inspect()
    require(check_network.is_isolated(network), 'network isolation')
    require(not DATA_ROOT.is_symlink() and not any(DATA_ROOT.iterdir()), 'fresh data')
    require(digest_file(Path('/opt/artex/artex')) == BACKEND_SHA256, 'pinned executable')
    client, process, downloads, previews, audits, logs = Client(), None, [], [], [], []
    tokens, stopped = [environment['PGPASSWORD']], 0
    try:
        for boot in (1, 2):
            child = dict(os.environ, ARTEX_SETUP_TOKEN=secrets.token_hex(32), ARTEX_LANG='en', ARTEX_SKILL_DIR='/opt/artex/skills')
            tokens.append(child['ARTEX_SETUP_TOKEN'])
            log = DATA_ROOT.parent / ('evidence-reference-' + str(boot) + '.log'); logs.append(log)
            with log.open('xb') as stream:
                process = subprocess.Popen(['/opt/artex/artex', '-addr', '127.0.0.1:8787', '-data', str(DATA_ROOT), '-proxy', ''], cwd=DATA_ROOT, env=child, stdout=stream, stderr=subprocess.STDOUT)
            for _ in range(120):
                require(process.poll() is None, 'backend exited')
                try:
                    auth = client.api('GET', '/api/auth/status')
                    break
                except OSError:
                    time.sleep(.25)
            else:
                raise RuntimeError('Evidence reference readiness expired')
            anonymous = Client()
            anonymous.api('GET', '/api/llm/profiles', expected=401)
            if boot == 1:
                require(auth.get('initialized') is False and auth.get('setup_token_required') is True, 'fresh auth')
                password = secrets.token_hex(32); tokens.append(password)
                client.token = client.api('POST', '/api/auth/init', {'password': password, 'setup_token': child['ARTEX_SETUP_TOKEN']})['token']
                tokens.append(client.token)
                audits.append(fixture.prepare())
            else:
                require(auth.get('initialized') is True, 'persisted auth')
                client.api('GET', '/api/llm/profiles'); audits.append(fixture.audit())
            traffic = client.api('GET', BASE)
            require(traffic.get('version') == 1 and [b['id'] for b in traffic.get('bindings', [])] == list(PAIRS), 'stored bindings')
            current = []
            for binding, sides in PAIRS.items():
                for side, name in sides.items():
                    current.append(client.download(boot, binding, side))
                    preview = client.api('GET', BASE + '/' + binding + '/body?side=' + side + '&offset=0')
                    require(preview.get('total') == fixture.body_manifest()[name]['size'] and preview.get('offset') == 0, 'preview metadata')
                    previews.append({'boot': boot, 'body': name, 'total': preview['total'], 'next_offset': preview.get('next_offset'), 'binary': preview.get('binary'), 'truncated': preview.get('truncated')})
            downloads.append(current); audits.append(fixture.audit())
            process.terminate(); require(process.wait(timeout=20) == 0, 'cooperative stop'); process = None; stopped += 1
        require(downloads[0] == downloads[1] and stopped == 2, 'persisted body equality')
        for path in logs:
            with path.open('rb') as stream:
                data = stream.read(4 * 1024 * 1024 + 1)
            require(len(data) <= 4 * 1024 * 1024 and all(token.encode() not in data for token in tokens), 'credential log audit')
        require(check_network.is_isolated(check_network.inspect()), 'final network')
        folder = Path(__file__).resolve().parent
        names = ('evidence_export_reference.py', 'evidence_fixture_guest.py', 'findings_seed_guest.py', 'findings_fixture_control.py')
        print(json.dumps({'passed': True, 'sourceCommit': SOURCE_COMMIT, 'backendSHA256': BACKEND_SHA256,
                          'sourceSHA256': {name: digest_file(folder / name) for name in names},
                          'networkCheckerSHA256': digest_file(Path(check_network.__file__)), 'networkProof': network,
                          'backendStarts': 2, 'cooperativeStops': stopped, 'credentialsAbsent': True,
                          'downloads': downloads, 'previews': previews, 'auditProofs': audits, 'browserUIAcceptance': False,
                          'declaredHTTPBodyScope': True, 'trailingWireBytesAudited': False}))
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=5)


if __name__ == '__main__':
    main()
