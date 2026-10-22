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
        self.assertIn('{backend,llm,chat}', result.stdout)
        self.assertTrue((root / 'script/chat_contract_fixture.py').is_file())
