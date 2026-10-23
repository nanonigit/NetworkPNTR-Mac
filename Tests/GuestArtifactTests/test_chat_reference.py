"""The disposable reference runner must expose the chat comparison contract."""
from pathlib import Path
import subprocess
import sys
import unittest


class ChatReferenceTests(unittest.TestCase):
    def test_comparison_cli_supports_chat(self):
        root = Path(__file__).resolve().parents[2]
        result = subprocess.run([sys.executable, str(root / 'script/compare_backend.py'), '--help'],
                                check=True, capture_output=True, text=True)
        self.assertIn('{backend,llm,chat,chat-history}', result.stdout)
        self.assertTrue((root / 'script/chat_contract_fixture.py').is_file())
        self.assertTrue((root / 'script/chat_history_contract_fixture.py').is_file())

    def test_host_execution_rejected_before_network(self):
        import runpy
        from unittest.mock import patch
        path = Path(__file__).resolve().parents[2] / 'script/chat_contract_fixture.py'
        with patch('platform.system', return_value='Darwin'), \
             patch('urllib.request.urlopen', side_effect=RuntimeError('network touched')) as request:
            with self.assertRaisesRegex(RuntimeError, 'isolated disposable reference'):
                runpy.run_path(str(path), run_name='__main__')
            request.assert_not_called()

    def test_unmarked_linux_execution_rejected_before_network(self):
        import runpy
        from unittest.mock import patch
        path = Path(__file__).resolve().parents[2] / 'script/chat_contract_fixture.py'
        with patch('platform.system', return_value='Linux'), patch.dict('os.environ', {}, clear=True), \
             patch('urllib.request.urlopen', side_effect=RuntimeError('network touched')) as request:
            with self.assertRaisesRegex(RuntimeError, 'isolated disposable reference'):
                runpy.run_path(str(path), run_name='__main__')
            request.assert_not_called()

    def test_import_has_no_network_side_effect(self):
        import runpy
        from unittest.mock import patch
        path = Path(__file__).resolve().parents[2] / 'script/chat_contract_fixture.py'
        with patch('urllib.request.urlopen', side_effect=RuntimeError('network touched')) as request:
            runpy.run_path(str(path), run_name='fixture_import_test')
            request.assert_not_called()
