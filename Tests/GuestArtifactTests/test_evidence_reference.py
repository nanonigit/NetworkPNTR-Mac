"""Independent reference streaming must reject framing/data failures before accepting files."""
import importlib.util
import http.client
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module
FIXTURE = load('evidence_fixture_guest', ROOT / 'script/evidence_fixture_guest.py')
with patch.dict('sys.modules', {'evidence_fixture_guest': FIXTURE}):
    REFERENCE = load('evidence_export_reference', ROOT / 'script/evidence_export_reference.py')

class Reply:
    def __init__(self, body, *, status=200, headers=None):
        self.body, self.status, self.offset = body, status, 0
        self.headers = headers if headers is not None else [('Content-Length', str(len(body)))]
        self.read_sizes = []
    def getheaders(self): return self.headers
    def read(self, size):
        self.read_sizes.append(size)
        chunk = self.body[self.offset:self.offset + min(size, 7)]
        self.offset += len(chunk); return chunk

class Connection:
    def __init__(self, reply): self.reply, self.calls, self.closed = reply, [], False
    def request(self, *args, **kwargs): self.calls.append((args, kwargs))
    def getresponse(self): return self.reply
    def close(self): self.closed = True

class EvidenceReferenceTests(unittest.TestCase):
    def setup_paths(self, root):
        FIXTURE.ROOT = root / 'evidence'
        REFERENCE.DOWNLOAD_ROOT = root / 'downloads'
        row = FIXTURE.body_manifest()['literal']
        path = FIXTURE.ROOT / 'blobs' / row['sha256'][:2] / (row['sha256'] + '.bin')
        path.parent.mkdir(parents=True, mode=0o700); path.write_bytes(FIXTURE.LITERAL); path.chmod(0o600)
        return row

    def test_partial_stream_compares_all_bytes_and_saves_exclusively_private(self):
        with tempfile.TemporaryDirectory() as directory:
            row = self.setup_paths(Path(directory)); reply = Reply(FIXTURE.LITERAL); connection = Connection(reply)
            client = REFERENCE.Client(connection_factory=lambda *a, **k: connection); client.token = 'fixture.jwt'
            result = client.download(1, '17001', 'request')
            self.assertEqual(result['bytes'], row['size']); self.assertEqual(result['sha256'], row['sha256']); self.assertTrue(result['full_byte_equal'])
            saved = REFERENCE.DOWNLOAD_ROOT / 'boot-1/literal.bin'
            self.assertEqual(saved.read_bytes(), FIXTURE.LITERAL); self.assertEqual(stat.S_IMODE(saved.stat().st_mode), 0o600)
            self.assertTrue(connection.closed); self.assertLessEqual(max(reply.read_sizes), 65536)
            self.assertEqual(connection.calls[0][0][:2], ('GET', '/api/exploration/findings/9101/traffic/17001/body?side=request&download=1'))
            with self.assertRaises(RuntimeError): client.download(1, '17001', 'request')
            self.assertEqual(saved.read_bytes(), FIXTURE.LITERAL)

    def test_status_length_encoding_truncation_corruption_and_excess_reader_data_fail_closed(self):
        for mode in range(7):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                row = self.setup_paths(Path(directory)); body = FIXTURE.LITERAL
                status = 403 if mode == 0 else 200
                headers = [('Content-Length', str(row['size']))]
                if mode == 1: headers = [('Content-Length', str(row['size'] + 1))]
                if mode == 2: headers += [('Content-Encoding', 'gzip')]
                if mode == 3: headers += [('Transfer-Encoding', 'chunked')]
                if mode == 4: body = body[:-1]
                if mode == 5: body = b'x' + body[1:]
                if mode == 6: body += b'x'
                connection = Connection(Reply(body, status=status, headers=headers))
                client = REFERENCE.Client(connection_factory=lambda *a, **k: connection); client.token = 'fixture.jwt'
                with self.assertRaises(RuntimeError): client.download(1, '17001', 'request')
                self.assertTrue(connection.closed)
                self.assertFalse((REFERENCE.DOWNLOAD_ROOT / 'boot-1/literal.bin').exists())

    def test_unknown_routes_sides_boots_and_injected_bearer_never_connect(self):
        factory = Mock()
        client = REFERENCE.Client(connection_factory=factory)
        for args in [(0, '17001', 'request'), (3, '17001', 'request'), (1, '9', 'request'), (1, '17001', '../response')]:
            with self.assertRaises(RuntimeError): client.download(*args)
        for method, path in [('GET', 'https://outside.invalid/'), ('POST', '/api/exploration/findings/9101/traffic'), ('DELETE', '/api/auth/status')]:
            with self.assertRaises(RuntimeError): client.api(method, path)
        client.token = 'bad\r\nInjected: yes'
        with self.assertRaises(RuntimeError): client.api('GET', '/api/auth/status')
        factory.assert_not_called()

    def test_bounded_json_and_deadline_are_checked_independently(self):
        for body in (b'bad json', b'[]', b'x' * (4 * 1024 * 1024 + 1)):
            connection = Connection(Reply(body)); client = REFERENCE.Client(connection_factory=lambda *a, **k: connection)
            with self.assertRaises(RuntimeError): client.api('GET', '/api/auth/status')
            self.assertTrue(connection.closed)
        connection = Connection(Reply(b'{"initialized":true}'))
        client = REFERENCE.Client(connection_factory=lambda *a, **k: connection)
        self.assertEqual(client.api('GET', '/api/auth/status'), {'initialized': True})
        factory = Mock(); client = REFERENCE.Client(connection_factory=factory, clock=lambda: 0); client.clock = lambda: 1000
        with self.assertRaises(RuntimeError): client.api('GET', '/api/auth/status')
        factory.assert_not_called()

    def test_host_main_rejects_before_any_file_or_process_operation(self):
        with patch.object(REFERENCE.platform, 'system', return_value='Darwin'), patch.object(REFERENCE.subprocess, 'Popen') as process, patch.object(REFERENCE.fixture, 'prepare') as prepare:
            with self.assertRaises(RuntimeError): REFERENCE.main()
            process.assert_not_called(); prepare.assert_not_called()

    def test_output_fstat_failure_reports_unknown_cleanup_and_closes_descriptor(self):
        with tempfile.TemporaryDirectory() as directory:
            self.setup_paths(Path(directory)); connection = Connection(Reply(FIXTURE.LITERAL))
            client = REFERENCE.Client(connection_factory=lambda *a, **k: connection)
            original_open = os.open; descriptors = []
            def tracked_open(*args, **kwargs):
                fd = original_open(*args, **kwargs); descriptors.append(fd); return fd
            try:
                with patch.object(REFERENCE.os, 'open', side_effect=tracked_open), patch.object(REFERENCE.os, 'fstat', side_effect=OSError('injected fstat')):
                    with self.assertRaisesRegex(RuntimeError, 'cleanup incomplete'): client.download(1, '17001', 'request')
                for fd in descriptors:
                    with self.assertRaises(OSError): os.fstat(fd)
            finally:
                for fd in descriptors:
                    try: os.close(fd)
                    except OSError: pass

    def test_context_creation_failure_closes_both_descriptors_without_double_close(self):
        with tempfile.TemporaryDirectory() as directory:
            self.setup_paths(Path(directory)); connection = Connection(Reply(FIXTURE.LITERAL))
            client = REFERENCE.Client(connection_factory=lambda *a, **k: connection)
            original_open, original_fdopen = os.open, os.fdopen; descriptors = []; calls = [0]
            def tracked_open(*args, **kwargs):
                fd = original_open(*args, **kwargs); descriptors.append(fd); return fd
            def fail_second(*args, **kwargs):
                calls[0] += 1
                if calls[0] == 2: raise OSError('injected context failure')
                return original_fdopen(*args, **kwargs)
            try:
                with patch.object(REFERENCE.os, 'open', side_effect=tracked_open), patch.object(REFERENCE.os, 'fdopen', side_effect=fail_second):
                    with self.assertRaises(RuntimeError): client.download(1, '17001', 'request')
                for fd in descriptors:
                    with self.assertRaises(OSError): os.fstat(fd)
                self.assertFalse((REFERENCE.DOWNLOAD_ROOT / 'boot-1/literal.bin').exists())
            finally:
                for fd in descriptors:
                    try: os.close(fd)
                    except OSError: pass

    def test_real_http_parser_compares_declared_body_and_does_not_claim_trailing_wire_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            row = self.setup_paths(Path(directory))
            wire = b'HTTP/1.1 200 OK\r\nContent-Length: ' + str(row['size']).encode() + b'\r\nConnection: close\r\n\r\n' + FIXTURE.LITERAL + b'outside declared HTTP body'
            sock = type('Socket', (), {'makefile': lambda self, *a, **k: io.BytesIO(wire)})()
            response = http.client.HTTPResponse(sock); response.begin()
            connection = Connection(response); client = REFERENCE.Client(connection_factory=lambda *a, **k: connection)
            proof = client.download(1, '17001', 'request')
            self.assertEqual(proof['bytes'], row['size']); self.assertTrue(proof['full_byte_equal'])
            self.assertEqual((REFERENCE.DOWNLOAD_ROOT / 'boot-1/literal.bin').read_bytes(), FIXTURE.LITERAL)

    def test_real_http_parser_rejects_truncated_or_wrong_declared_body(self):
        for length, body in [(52, FIXTURE.LITERAL[:-1]), (53, FIXTURE.LITERAL + b'x')]:
            with self.subTest(length=length), tempfile.TemporaryDirectory() as directory:
                self.setup_paths(Path(directory))
                wire = b'HTTP/1.1 200 OK\r\nContent-Length: ' + str(length).encode() + b'\r\nConnection: close\r\n\r\n' + body
                sock = type('Socket', (), {'makefile': lambda self, *a, **k: io.BytesIO(wire)})()
                response = http.client.HTTPResponse(sock); response.begin()
                client = REFERENCE.Client(connection_factory=lambda *a, **k: Connection(response))
                with self.assertRaises(RuntimeError): client.download(1, '17001', 'request')
                self.assertFalse((REFERENCE.DOWNLOAD_ROOT / 'boot-1/literal.bin').exists())
