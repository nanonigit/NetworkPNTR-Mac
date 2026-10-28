import importlib.util
import os
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'script/captured_fixture_guest.py'


def load():
    spec = importlib.util.spec_from_file_location('captured_fixture_guest', SCRIPT)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


class CaptureRuntimeTests(unittest.TestCase):
    def test_guest_recorder_is_loopback_only_and_network_stays_absent(self):
        source = (ROOT / 'guest/backend-init').read_text()
        self.assertIn('-proxy 127.0.0.1:8788', source)
        self.assertNotIn('-proxy 0.0.0.0', source)
        self.assertIn('python3 /opt/artex-mac/check_network.py', source)
        self.assertNotIn('docker.sock', source)

    def test_fixed_exchange_manifest_has_page_and_body_boundaries(self):
        fixture = load(); rows = fixture.exchange_manifest()
        self.assertEqual(len(rows), 29)
        self.assertEqual({row['method'] for row in rows}, {'GET', 'POST'})
        self.assertEqual(len({row['url'] for row in rows}), 29)
        self.assertTrue(all(row['url'].startswith('http://127.0.0.1:8799/f5-captured/') for row in rows))
        self.assertEqual(rows[0]['request_size'], 0)
        self.assertTrue(any(row['response_size'] == 0 for row in rows))
        self.assertTrue(any(row['response_size'] > 8192 for row in rows))
        self.assertTrue(any(row['response_size'] > 256*1024 for row in rows))
        literal = fixture.response_body(1)
        self.assertTrue(literal.startswith(b'\xef\xbb\xbf')); self.assertIn('e\u0301'.encode(), literal)
        with self.assertRaises(RuntimeError): fixture.response_body(-1)
        with self.assertRaises(RuntimeError): fixture.request_body(29)

    def test_host_execution_is_rejected_before_listener_or_database(self):
        fixture = load()
        with patch.object(fixture.platform, 'system', return_value='Darwin'), patch.object(fixture, 'HTTPServer') as server:
            with self.assertRaises(RuntimeError): fixture.prepare()
            server.assert_not_called()

    def test_environment_requires_flags_and_network_proof(self):
        fixture = load(); seed = types.SimpleNamespace(validate_environment=lambda: {'fixture': 'safe'})
        network = types.SimpleNamespace(inspect=lambda: {'network_hardware_devices': 0}, is_isolated=lambda value: True)
        with patch.dict(sys.modules, {'findings_seed_guest': seed, 'check_network': network}), patch.object(fixture.platform,'system',return_value='Linux'), patch.object(fixture.platform,'machine',return_value='aarch64'), patch.object(fixture.os,'getuid',return_value=1000), patch.dict(os.environ, {'ARTEX_CAPTURE_FIXTURE': '1'},clear=True):
            self.assertEqual(fixture.environment(), {'fixture': 'safe'})
            with patch.dict(os.environ, {'ARTEX_CAPTURE_FIXTURE': '0'}):
                with self.assertRaises(RuntimeError): fixture.environment()
            with patch.object(network,'is_isolated',return_value=False):
                with self.assertRaises(RuntimeError): fixture.environment()

    def test_http_capture_guard_uses_fixed_ports_and_no_environment_proxy(self):
        fixture = load(); source = SCRIPT.read_text()
        self.assertIn("HTTPConnection('127.0.0.1', 8788", source)
        self.assertNotIn('urlopen(', source)
        self.assertEqual(fixture.FINDING_ID, '9101')
        self.assertNotIn('sqlite3', source)


if __name__ == '__main__': unittest.main()
