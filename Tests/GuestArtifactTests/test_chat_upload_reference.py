"""The upload reference must be inert outside its owned disposable container."""
import hashlib
from pathlib import Path
import runpy
import subprocess
import sys
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'script/chat_upload_contract_fixture.py'


class ChatUploadReferenceTests(unittest.TestCase):
    def load(self):
        return runpy.run_path(str(FIXTURE), run_name='upload_fixture_import_test')

    def test_cli_and_import_are_inert(self):
        result = subprocess.run([sys.executable, str(ROOT / 'script/compare_backend.py'), '--help'],
                                check=True, capture_output=True, text=True)
        self.assertIn('chat-upload', result.stdout)
        with patch('http.client.HTTPConnection', side_effect=AssertionError('network touched')) as network:
            self.load()
            network.assert_not_called()

    def test_host_wrong_user_and_unmarked_linux_fail_before_network(self):
        for system, uid, environment in [('Darwin', 1000, {'ARTEX_DISPOSABLE_REFERENCE': '1'}),
                                          ('Linux', 0, {'ARTEX_DISPOSABLE_REFERENCE': '1'}),
                                          ('Linux', 1000, {})]:
            with patch('platform.system', return_value=system), patch('os.getuid', return_value=uid), \
                 patch.dict('os.environ', environment, clear=True), \
                 patch('http.client.HTTPConnection', side_effect=AssertionError('network touched')) as network:
                with self.assertRaisesRegex(RuntimeError, 'isolated disposable reference'):
                    runpy.run_path(str(FIXTURE), run_name='__main__')
                network.assert_not_called()

    def test_binary_empty_repeated_filename_and_header_escaping(self):
        module = self.load()
        parts = [('same.txt', 3, lambda: iter([b'\0\xffA'])), ('same.txt', 0, lambda: iter([])),
                 ('quote"\r\n.txt', 1, lambda: iter([b'x']))]
        body = module['Multipart'](parts, boundary='fixture')
        wire = b''.join(body.chunks())
        self.assertEqual(len(wire), body.length)
        self.assertIn(b'filename="quote%22%0D%0A.txt"\r\n', wire)
        self.assertEqual(wire.count(b'filename="same.txt"'), 2)
        self.assertIn(b'\0\xffA\r\n', wire)
        self.assertTrue(wire.endswith(b'--fixture--\r\n'))

    def test_exact_limit_counts_overhead_and_chunks_stay_bounded(self):
        module = self.load(); multipart, zero = module['Multipart'], module['zero_blocks']
        overhead = multipart([('limit.bin', 0, lambda: iter([]))]).length
        size = 128 * 1024 * 1024 - overhead
        body = multipart([('limit.bin', size, lambda: zero(size))])
        self.assertEqual(body.length, 128 * 1024 * 1024)
        total, maximum = 0, 0
        for chunk in body.chunks():
            total += len(chunk); maximum = max(maximum, len(chunk))
        self.assertEqual(total, body.length)
        self.assertLessEqual(maximum, 65536)
        oversized = multipart([('limit.bin', size + 1, lambda: zero(size + 1))])
        self.assertEqual(oversized.length, 128 * 1024 * 1024 + 1)

    def test_short_extra_and_invalid_synthetic_inputs_are_rejected(self):
        multipart = self.load()['Multipart']
        for declared, data in [(2, b'x'), (1, b'xx')]:
            with self.assertRaisesRegex(RuntimeError, 'content length'):
                list(multipart([('file', declared, lambda: iter([data]))]).chunks())
        for parts, boundary in [([], 'valid'), ([('file', -1, lambda: iter([]))], 'valid'),
                                ([('file', 0, lambda: iter([]))], 'bad\r\nboundary')]:
            with self.assertRaises(ValueError):
                multipart(parts, boundary=boundary)

    def digest_fixture(self, data, headers=None, status=200):
        module = self.load()
        response = Mock(status=status)
        response.getheaders.return_value = headers if headers is not None else [('Content-Length', str(len(data)))]
        remaining = [data]
        def read(count):
            self.assertLessEqual(count, 65536)
            chunk, remaining[0] = remaining[0][:count], remaining[0][count:]
            return chunk
        response.read.side_effect = read
        connection = Mock()
        connection.getresponse.return_value = response
        return module, response, connection

    def test_download_digest_reads_full_content_in_bounded_blocks(self):
        data = bytes(range(256)) * (6 * 4096)
        module, response, connection = self.digest_fixture(data)
        with patch('http.client.HTTPConnection', return_value=connection):
            digest = module['Client']().digest('/api/workspace/download?path=fixture', len(data))
        self.assertEqual(digest, {'downloaded_size': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'full_content_hash_verified': True})
        self.assertGreater(response.read.call_count, 1)
        connection.close.assert_called_once()

    def test_download_digest_rejects_truncated_extra_or_changed_length(self):
        for data, expected, headers in [(b'x', 2, [('Content-Length', '2')]),
                                         (b'xxx', 2, [('Content-Length', '2')]),
                                         (b'x', 2, [('Content-Length', '1')])]:
            module, _, connection = self.digest_fixture(data, headers)
            with patch('http.client.HTTPConnection', return_value=connection):
                with self.assertRaises(RuntimeError):
                    module['Client']().digest('/api/workspace/download?path=fixture', expected)
            connection.close.assert_called_once()

    def test_download_digest_rejects_ambiguous_encoded_or_unsuccessful_response(self):
        for status, headers in [(401, [('Content-Length', '0')]), (206, [('Content-Length', '0')]),
                                 (200, []), (200, [('Content-Length', '0'), ('Content-Length', '0')]),
                                 (200, [('Content-Length', '0'), ('Transfer-Encoding', 'chunked')]),
                                 (200, [('Content-Length', '0'), ('Content-Encoding', 'gzip')])]:
            module, _, connection = self.digest_fixture(b'', headers, status)
            with patch('http.client.HTTPConnection', return_value=connection):
                with self.assertRaises(RuntimeError):
                    module['Client']().digest('/api/workspace/download?path=fixture', 0)
            connection.close.assert_called_once()
