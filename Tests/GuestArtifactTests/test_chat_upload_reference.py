"""The upload reference must be inert outside its owned disposable container."""
from pathlib import Path
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch

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
