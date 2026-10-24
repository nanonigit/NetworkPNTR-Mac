"""Attachment state reference remains inert and scoped to disposable Linux."""
from pathlib import Path
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'script/chat_attachment_state_contract_fixture.py'

class AttachmentStateReferenceTests(unittest.TestCase):
    def load(self):
        return runpy.run_path(str(FIXTURE),run_name='attachment_reference_import')

    def test_cli_mode_and_import_are_inert(self):
        result = subprocess.run([sys.executable,str(ROOT/'script/compare_backend.py'),'--help'],capture_output=True,text=True,check=True)
        self.assertIn('chat-attachment-state',result.stdout)
        with patch('http.client.HTTPConnection',side_effect=AssertionError('network touched')) as connection:
            self.load()
            connection.assert_not_called()

    def test_host_user_and_marker_guard_precedes_network(self):
        for system, uid, environment in [('Darwin',1000,{'ARTEX_DISPOSABLE_REFERENCE':'1'}),('Linux',0,{'ARTEX_DISPOSABLE_REFERENCE':'1'}),('Linux',1000,{})]:
            with patch('platform.system',return_value=system),patch('os.getuid',return_value=uid),patch.dict('os.environ',environment,clear=True),patch('http.client.HTTPConnection',side_effect=AssertionError('network touched')) as connection:
                with self.assertRaisesRegex(RuntimeError,'isolated disposable reference'):
                    runpy.run_path(str(FIXTURE),run_name='__main__')
                connection.assert_not_called()

    def test_small_multipart_preserves_distinct_unicode_names_and_empty_bytes(self):
        fixture = self.load()
        content_type, body = fixture['multipart']([('é.txt',b'\x01'),('e\u0301.txt',b'\x02'),('empty.txt',b'')])
        self.assertIn('boundary=',content_type)
        self.assertIn('filename="é.txt"'.encode(),body)
        self.assertIn('filename="e\u0301.txt"'.encode(),body)
        self.assertIn(b'\r\n\x01\r\n',body); self.assertIn(b'\r\n\x02\r\n',body)
        for parts in [[],[('../file',b'x')],[('bad\r\n',b'x')],[('a',b'x'*65537)]]:
            with self.assertRaises(ValueError): fixture['multipart'](parts)
