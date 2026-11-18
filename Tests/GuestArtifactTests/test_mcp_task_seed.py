"""The selected-task fixture may operate only on a fresh isolated guest database."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'script/mcp_task_seed_guest.py'
spec = importlib.util.spec_from_file_location('mcp_task_seed', SOURCE)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
ENV = {'NETWORKPNTR_MCP_TASK_FIXTURE': '1', 'ARTEX_PG_DSN': 'postgres://artex:' + 'a' * 64 + '@127.0.0.1:5432/artex?sslmode=disable'}


class MCPTaskSeedTests(unittest.TestCase):
    def setUp(self):
        child = patch.object(fixture.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0))
        self.child = child.start()
        self.addCleanup(child.stop)

    def run_fixture(self, env=None, system='Linux', machine='aarch64', uid=1000):
        with patch.dict(os.environ, ENV if env is None else env, clear=True), patch.object(fixture.platform, 'system', return_value=system), patch.object(fixture.platform, 'machine', return_value=machine), patch.object(fixture.os, 'getuid', return_value=uid), contextlib.redirect_stdout(io.StringIO()) as output:
            fixture.main()
            return json.loads(output.getvalue())

    def test_non_guest_and_missing_marker_rejected_without_child(self):
        for kwargs in [{'system': 'Darwin'}, {'machine': 'x86_64'}, {'uid': 0}, {'env': {**ENV, 'NETWORKPNTR_MCP_TASK_FIXTURE': '0'}}]:
            with self.subTest(case=kwargs):
                with self.assertRaises(RuntimeError):
                    self.run_fixture(**kwargs)
                self.child.assert_not_called()

    def test_dsn_injection_and_other_destinations_refused_without_disclosure(self):
        good = ENV['ARTEX_PG_DSN']
        for bad in ['', good.replace('127.0.0.1', 'outside.invalid'), good.replace('127.0.0.1', 'localhost'), good.replace(':5432', ':5433'), good.replace(':5432', ':bad'), good + '&options=unsafe', good + '#private', good.replace('/artex?', '/postgres?'), good.replace('artex:', 'root:'), good.replace('a' * 64, 'private-secret')]:
            with self.subTest(case=bad):
                with self.assertRaises(RuntimeError) as raised:
                    self.run_fixture(env={**ENV, 'ARTEX_PG_DSN': bad})
                self.assertNotIn('a' * 64, str(raised.exception))
                self.assertNotIn('private-secret', str(raised.exception))

    def test_fixed_transaction_and_sanitized_child_environment(self):
        proof = self.run_fixture(env={**ENV, 'PGHOSTADDR': 'outside.invalid', 'PGOPTIONS': 'unsafe', 'PATH': '/unsafe'})
        args, kwargs = self.child.call_args
        self.assertEqual(args[0], ['/usr/libexec/postgresql16/psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1'])
        self.assertEqual(kwargs['input'], fixture.SQL.encode())
        self.assertEqual(kwargs['env']['PGHOST'], '127.0.0.1')
        self.assertNotIn('PGHOSTADDR', kwargs['env'])
        self.assertNotIn('PGOPTIONS', kwargs['env'])
        self.assertEqual(kwargs['stdout'], subprocess.DEVNULL)
        self.assertEqual(kwargs['stderr'], subprocess.DEVNULL)
        self.assertEqual(proof, {'mcp_task_fixture_seeded': True, 'linux_guest': True, 'uid': 1000, 'task_ids': ['7201', '7202']})

    def test_timeout_suppresses_child_error_details_and_success(self):
        self.child.side_effect = subprocess.TimeoutExpired('private-child-command', 15, stderr=b'private-child-detail')
        with contextlib.redirect_stdout(io.StringIO()) as output:
            with self.assertRaisesRegex(RuntimeError, '^MCP task fixture transaction failed$') as raised:
                self.run_fixture()
        self.assertEqual(output.getvalue(), '')
        self.assertNotIn('private', str(raised.exception))

    def test_transaction_failure_never_reports_success(self):
        self.child.return_value = subprocess.CompletedProcess([], 1)
        with self.assertRaisesRegex(RuntimeError, '^MCP task fixture transaction failed$'):
            self.run_fixture()
