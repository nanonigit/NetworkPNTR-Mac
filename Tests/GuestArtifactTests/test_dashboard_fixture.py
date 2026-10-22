"""The developer seed must fail closed even when Python optimization is enabled."""
from pathlib import Path
import subprocess
import sys
import unittest


class DashboardFixtureBoundaryTests(unittest.TestCase):
    def test_optimized_python_rejects_host_before_any_child_process(self):
        source = Path(__file__).resolve().parents[2] / 'script' / 'dashboard_seed_guest.py'
        program = r'''
import importlib.util, os, sys
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('fixture', sys.argv[1])
fixture = importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture)
mode = sys.argv[2]
os.environ['ARTEX_PG_DSN'] = 'postgres://fixture:dummy@outside.invalid/artex' if mode == 'database' else 'postgres://fixture:dummy@127.0.0.1/artex'
expected = 'Fixture requires the guest loopback artex database' if mode == 'database' else 'Fixture requires an isolated Linux guest'
with patch.object(fixture.platform, 'system', return_value='Darwin' if mode == 'host' else 'Linux'), patch.object(fixture.platform, 'machine', return_value='aarch64'), patch.object(fixture.os, 'getuid', return_value=0 if mode == 'uid' else 1000), patch.object(fixture.subprocess, 'run', side_effect=RuntimeError('unexpected child process')):
    try:
        fixture.main()
    except RuntimeError as error:
        if str(error) == expected:
            print('host rejected before database access')
            sys.exit(0)
    sys.exit(1)
'''
        for mode in ['host', 'uid', 'database']:
            with self.subTest(boundary=mode):
                result = subprocess.run([sys.executable, '-O', '-c', program, str(source), mode], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, 'Optimized interpreter must enforce the host boundary')
                self.assertEqual(result.stdout.strip(), 'host rejected before database access')
