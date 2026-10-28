"""Fixed real loopback traffic, diagnostic Linux guest only. No CLI destination or SQL input."""
import contextlib
import hashlib
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, HTTPServer
import io
import os
import platform
import re
import socket
import threading
import time

FINDING_ID = '9101'
TARGET = 'http://127.0.0.1:8799/f5-captured/'
LITERAL = '\ufeffe\u0301 English Japanese \u65e5\u672c\u8a9e \u4e2d\u6587 \ud55c\uad6d\uc5b4\r\n'.encode()


def require(value, reason):
    if not value:
        raise RuntimeError('Captured fixture ' + reason)


def ordinal(value):
    require(type(value) is int and 0 <= value < 29, 'fixed ordinal')
    return value


def request_body(index):
    ordinal(index)
    return b'' if index % 2 == 0 else LITERAL + str(index).encode()


def response_body(index):
    ordinal(index)
    if index == 0: return b''
    if index == 1: return LITERAL
    if index == 2: return bytes(range(256)) * 256 + b'END'
    if index == 3: return 'e\u0301'.encode() * 3001
    if index == 4: return bytes(range(256)) * 1025 + b'Z'
    return ('F5 captured ordinal %02d\r\n' % index).encode()


def content_type(index):
    return 'application/octet-stream' if index in (2, 4) else 'text/plain; charset=utf-8'


def exchange_manifest():
    rows = []
    for index in range(29):
        request, response = request_body(index), response_body(index)
        rows.append(dict(ordinal=index, method='GET' if index % 2 == 0 else 'POST',
                         url=TARGET + '%02d' % index, request_size=len(request), response_size=len(response),
                         request_sha256=hashlib.sha256(request).hexdigest(), response_sha256=hashlib.sha256(response).hexdigest(),
                         content_type=content_type(index), status=200))
    return rows


def environment():
    require(platform.system() == 'Linux' and platform.machine() == 'aarch64' and os.getuid() == 1000, 'owned Linux/aarch64/UID1000 only')
    require(os.environ.get('ARTEX_CAPTURE_FIXTURE') == '1', 'explicit diagnostic flag')
    from findings_seed_guest import validate_environment
    import check_network
    result = validate_environment()
    require(check_network.is_isolated(check_network.inspect()), 'zero external connectivity')
    return result


class FixedHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    # StreamRequestHandler.setup applies this before request-line/header parsing.
    timeout = 3
    def log_message(self, *args): pass
    def do_GET(self): self.exchange()
    def do_POST(self): self.exchange()
    def exchange(self):
        self.connection.settimeout(3)
        match = re.fullmatch(r'/f5-captured/([0-9]{2})', self.path)
        if not match or not 0 <= int(match[1]) < 29:
            self.send_error(404); return
        index = int(match[1]); expected = request_body(index)
        if self.command != ('GET' if index % 2 == 0 else 'POST') or self.headers.get('Content-Length', '0') != str(len(expected)):
            self.send_error(400); return
        if self.rfile.read(len(expected)) != expected:
            self.send_error(400); return
        body = response_body(index)
        self.send_response_only(200)
        self.send_header('Content-Type', content_type(index)); self.send_header('Content-Length', str(len(body)))
        self.send_header('X-F5-Ordinal', '%02d' % index); self.send_header('Connection', 'close')
        self.end_headers(); self.wfile.write(body); self.wfile.flush(); self.close_connection = True


def read_records(client):
    environment()
    page = client.api('GET', '/api/traffic?page=0&size=500')
    rows = page.get('exchanges')
    require(type(rows) is list and len(rows) == page.get('count') == page.get('total') == 29
            and page.get('page') == 0 and page.get('size') == 500, 'exact recorded index')
    expected = {row['url']: row for row in exchange_manifest()}
    require(len({row.get('id') for row in rows}) == 29 and {row.get('url') for row in rows} == set(expected), 'recorded identities')
    for row in rows:
        spec = expected[row['url']]
        require(isinstance(row.get('id'), str) and re.fullmatch(r'[0-9]{1,20}-[0-9]{4}', row['id']) is not None
                and row.get('method') == spec['method'] and row.get('status') == 200
                and row.get('resp_len') == spec['response_size'] and row.get('content_type') == spec['content_type']
                and row.get('host') == '127.0.0.1', 'recorded metadata')
    return sorted(rows, key=lambda row: expected[row['url']]['ordinal'])


def capture(client):
    environment()
    page = client.api('GET', '/api/traffic?page=0&size=500')
    require(page.get('count') == page.get('total') == 0 and page.get('exchanges') == [], 'fresh empty capture index')
    deadline = time.monotonic() + 60
    while True:
        try:
            with socket.create_connection(('127.0.0.1', 8788), timeout=1): break
        except OSError:
            require(time.monotonic() < deadline, 'recording listener readiness')
            time.sleep(.05)
    server = HTTPServer(('127.0.0.1', 8799), FixedHandler, bind_and_activate=False)
    worker = None
    try:
        server.allow_reuse_address = False; server.server_bind(); server.server_activate()
        worker = threading.Thread(target=lambda: server.serve_forever(poll_interval=.05), daemon=True)
        worker.start()
        for spec in exchange_manifest():
            require(time.monotonic() < deadline, 'capture deadline')
            connection = HTTPConnection('127.0.0.1', 8788, timeout=5)
            try:
                body = request_body(spec['ordinal'])
                connection.request(spec['method'], spec['url'], body=body,
                                   headers={'Connection': 'close', 'Content-Type': 'text/plain; charset=utf-8', 'Content-Length': str(len(body))})
                response = connection.getresponse()
                received = response.read(spec['response_size'] + 1)
                require(response.status == 200 and response.getheader('Content-Length') == str(spec['response_size'])
                        and received == response_body(spec['ordinal']), 'actual proxy response bytes')
            finally:
                connection.close()
    finally:
        if worker is not None:
            server.shutdown(); worker.join(timeout=5)
        server.server_close()
        require(worker is None or not worker.is_alive(), 'target server terminal cleanup')
    environment()
    return read_records(client)


def audit_activity(bindings=0, snapshots=0):
    env = environment()
    require((bindings, snapshots) in ((0, 0), (2, 2), (1, 2)), 'fixed activity phase')
    import findings_fixture_control as control
    counts = control._query(env)
    require(set(counts) == set(control.ZERO_KEYS) | set(control.COUNT_QUERIES), 'activity keys')
    require(all(type(value) is int and value >= 0 for value in counts.values()), 'activity count types')
    allowed = {'traffic_bindings': bindings, 'traffic_snapshots': snapshots}
    require(all(counts[key] == allowed.get(key, 0) for key in control.ZERO_KEYS), 'no agents or foreign activity')
    require([counts[key] for key in ('tasks','explorations','relations','companies','assets','findings','finding_nodes')] == [11,11,1,1,3,33,32]
            and counts['events'] == 0, 'terminal fixture counts')
    return counts


def prepare(client=None):
    environment()
    require(client is not None, 'fixed client required')
    import findings_seed_guest as seed
    import findings_fixture_control as control
    control.audit(fresh=True)
    with contextlib.redirect_stdout(io.StringIO()): seed.main()
    control.audit(fresh=False)
    rows = capture(client)
    return {'captured_fixture': True, 'uid': os.getuid(), 'records': rows, 'manifest': exchange_manifest(), 'counts': audit_activity()}
