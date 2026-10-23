"""Never seed a host database; all subprocess effects are mocked in these tests."""
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from types import SimpleNamespace

PATH = Path(__file__).resolve().parents[2] / 'script/chat_history_seed_guest.py'
spec = importlib.util.spec_from_file_location('chat_history_seed', PATH)
seed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seed)


class ChatHistorySeedTests(unittest.TestCase):
    def test_host_and_wrong_uid_rejected_before_subprocess(self):
        for system, machine, uid in [('Darwin', 'arm64', 1000), ('Linux', 'x86_64', 1000), ('Linux', 'aarch64', 0)]:
            with self.subTest(system=system, machine=machine, uid=uid), \
                 patch.object(seed.platform, 'system', return_value=system), \
                 patch.object(seed.platform, 'machine', return_value=machine), \
                 patch.object(seed.os, 'getuid', return_value=uid), patch.object(seed.subprocess, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, 'isolated Linux guest'):
                    seed.main()
                run.assert_not_called()

    def execute(self, dsn, phase='initial', returncode=0):
        with patch.object(seed.platform, 'system', return_value='Linux'), \
             patch.object(seed.platform, 'machine', return_value='aarch64'), \
             patch.object(seed.os, 'getuid', return_value=1000), \
             patch.dict(seed.os.environ, {'ARTEX_PG_DSN': dsn}, clear=True), \
             patch.object(seed.subprocess, 'run', return_value=SimpleNamespace(returncode=returncode)) as run, \
             patch('sys.stdout', new_callable=io.StringIO) as output:
            seed.main(phase)
            return run.call_args, output.getvalue()

    def test_remote_database_and_invalid_phase_rejected(self):
        for dsn in ['postgres://u:p@postgres/artex', 'postgres://u:p@127.0.0.1/other', 'postgres://u:p@127.0.0.1:9999/artex']:
            with self.subTest(dsn=dsn), self.assertRaisesRegex(RuntimeError, 'guest loopback'):
                self.execute(dsn)
        with self.assertRaisesRegex(RuntimeError, 'phase'):
            self.execute('postgres://u:p@127.0.0.1:5432/artex', 'unknown')

    def test_initial_append_sql_and_private_password_environment(self):
        for phase, sql in [('initial', seed.SQL), ('append', seed.APPEND_SQL)]:
            with self.subTest(phase=phase):
                call, output = self.execute('postgres://artex:fixture%21@127.0.0.1:5432/artex', phase)
                self.assertEqual(call.args[0], ['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1'])
                self.assertEqual(call.kwargs['input'], sql.encode())
                self.assertEqual(call.kwargs['env']['PGPASSWORD'], 'fixture!')
                self.assertNotIn('fixture!', str(call.args))
                self.assertEqual(json.loads(output), {'chat_history_seeded': phase, 'linux_guest': True, 'aarch64': True, 'uid': 1000})

    def test_transaction_failure_sanitized(self):
        with self.assertRaisesRegex(RuntimeError, '^Chat fixture transaction failed$'):
            self.execute('postgres://artex:private@127.0.0.1/artex', returncode=1)
