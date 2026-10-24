import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('user_body_reference', ROOT / 'script/chat_user_body_reference.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)

class UserBodyReferenceTests(unittest.TestCase):
    def test_scope_guard_runs_before_http(self):
        with patch.object(fixture.platform, 'system', return_value='Darwin'), patch.object(fixture.Client, 'request') as request:
            with self.assertRaisesRegex(RuntimeError, 'disposable'):
                fixture.main('prepare')
            request.assert_not_called()

    def test_small_multipart_keeps_unicode_and_empty_file(self):
        content_type, body = fixture.multipart([('e\u0301-a6.txt', b'fixture'), ('empty-a6.txt', b'')])
        self.assertIn('multipart/form-data', content_type)
        self.assertIn('e\u0301-a6.txt'.encode(), body)
        self.assertIn(b'fixture\r\n', body)
        self.assertIn(b'filename="empty-a6.txt"', body)
        with self.assertRaises(ValueError):
            fixture.multipart([('../escape', b'')])

    def test_multipart_limit_includes_closing_boundary(self):
        content_type, empty = fixture.multipart([('a', b'')])
        closing_size = len(('--' + content_type.split('boundary=', 1)[1] + '--\r\n').encode())
        _, exact = fixture.multipart([('a', b'x' * (65536 - len(empty)))])
        self.assertEqual(len(exact), 65536)
        with self.assertRaises(ValueError):
            fixture.multipart([('a', b'x' * (65536 - len(empty) + closing_size))])

    def test_cleanup_attempts_files_and_other_owners_after_one_db_failure(self):
        class Client:
            def __init__(self): self.paths = []
            def request(self, method, path, body=None):
                self.paths.append(path)
                return (500, {}) if path == '/api/conversations/7' else (404, {})
        client = Client()
        with self.assertRaisesRegex(RuntimeError, 'cleanup'):
            fixture.cleanup(client, [7, 8])
        self.assertEqual(len(client.paths), 4)
        self.assertIn('/api/workspace/delete?path=sessions%2Fconv-7', client.paths)
        self.assertIn('/api/workspace/delete?path=sessions%2Fconv-8', client.paths)
        with self.assertRaises(ValueError): fixture.cleanup(client, [0])

if __name__ == '__main__': unittest.main()
