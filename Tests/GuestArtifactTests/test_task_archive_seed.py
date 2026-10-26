"""Fixed archive fixtures must never become a host/database command interface."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'script' / 'task_archive_seed_guest.py'
spec = importlib.util.spec_from_file_location('archive_seed', SOURCE)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)

ENV = {'ARTEX_ARCHIVE_FIXTURE': '1', 'ARTEX_PG_DSN': 'postgres://artex:' + 'a' * 64 + '@127.0.0.1:5432/artex?sslmode=disable'}


class ArchiveSeedTests(unittest.TestCase):
    def validate(self, env=None, system='Linux', machine='aarch64', uid=1000):
        with patch.dict(os.environ, ENV if env is None else env, clear=True), patch.object(fixture.platform, 'system', return_value=system), patch.object(fixture.platform, 'machine', return_value=machine), patch.object(fixture.os, 'getuid', return_value=uid):
            return fixture.validate_environment()

    def test_host_arch_uid_marker_refused_before_child(self):
        for kwargs in [{'system': 'Darwin'}, {'machine': 'x86_64'}, {'uid': 0}, {'env': {**ENV, 'ARTEX_ARCHIVE_FIXTURE': '0'}}]:
            with self.subTest(kwargs=kwargs), patch.object(fixture.subprocess, 'run') as child:
                with self.assertRaises(RuntimeError):
                    self.validate(**kwargs)
                child.assert_not_called()

    def test_dsn_must_be_exact_guest_loopback_without_options_or_secret_disclosure(self):
        good = ENV['ARTEX_PG_DSN']
        invalid = ['', 'postgres://unix', good.replace('127.0.0.1', 'outside.invalid'), good.replace('127.0.0.1', 'localhost'), good.replace(':5432', ':5433'), good.replace(':5432', ':bad'), good.replace('/artex?', '/postgres?'), good.replace('artex:', 'root:'), good.replace('a' * 64, 'not-a-credential'), good + '&options=unsafe', good + '#fragment', good.replace('sslmode=disable', 'sslmode=require'), good + '&sslmode=disable']
        for dsn in invalid:
            with self.subTest(case=invalid.index(dsn)):
                with self.assertRaises(RuntimeError) as raised:
                    self.validate(env={**ENV, 'ARTEX_PG_DSN': dsn})
                self.assertNotIn(dsn or 'never-matches', str(raised.exception))
                self.assertNotIn('a' * 64, str(raised.exception))

    def test_child_environment_drops_inherited_postgres_overrides(self):
        result = self.validate(env={**ENV, 'PGHOSTADDR': 'outside.invalid', 'PGOPTIONS': 'unsafe', 'PGSERVICEFILE': 'private', 'HOME': '/private', 'PATH': '/unsafe'})
        self.assertEqual(result['PGHOST'], '127.0.0.1')
        self.assertEqual(result['PGPORT'], '5432')
        self.assertEqual(result['PGUSER'], 'artex')
        self.assertEqual(set(result), {'PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD', 'PGCONNECT_TIMEOUT', 'PGCLIENTENCODING'})
        self.assertNotEqual(result['PATH'], '/unsafe')

    def test_exclusive_fixture_bytes_and_proof_refuse_reuse_without_clobber(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            proof = fixture.write_files(root)
            self.assertEqual(len(proof), len(fixture.FILES))
            for item, (name, data) in zip(proof, fixture.FILES):
                self.assertEqual((root / name).read_bytes(), data)
                self.assertEqual(item['path'], name)
                self.assertEqual(item['size'], len(data))
                self.assertEqual(item['sha256'], fixture.hashlib.sha256(data).hexdigest())
            with self.assertRaises(RuntimeError):
                fixture.write_files(root)
            for name, data in fixture.FILES:
                self.assertEqual((root / name).read_bytes(), data)

    def test_symlink_or_nonempty_task_root_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); outside = root / 'outside'; outside.mkdir()
            (root / 'tasks').symlink_to(outside, target_is_directory=True)
            with self.assertRaises(RuntimeError):
                fixture.validate_paths(root)
            (root / 'tasks').unlink(); (root / 'tasks').mkdir(); (root / 'tasks' / 'user.txt').write_text('keep')
            with self.assertRaises(RuntimeError):
                fixture.write_files(root)
            self.assertEqual((root / 'tasks' / 'user.txt').read_text(), 'keep')
            alias = root / 'alias'; alias.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(RuntimeError):
                fixture.validate_paths(alias)

    def test_sql_failure_stops_before_files_and_success_is_fixed_proof_only(self):
        with patch.object(fixture, 'validate_environment', return_value={'PATH': '/safe'}), patch.object(fixture, 'validate_paths'), patch.object(fixture, 'write_files', return_value=[{'path': 'fixed', 'size': 0, 'sha256': '0' * 64}]) as files:
            with patch.object(fixture.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)) as child, contextlib.redirect_stdout(io.StringIO()) as output:
                with self.assertRaises(RuntimeError):
                    fixture.main()
                self.assertEqual(output.getvalue(), '')
                files.assert_not_called(); self.assertEqual(child.call_count, 1)
            with patch.object(fixture.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as child, contextlib.redirect_stdout(io.StringIO()) as output:
                fixture.main()
                args, kwargs = child.call_args
                self.assertEqual(args[0], ['psql', '-X', '--no-password', '-q', '-v', 'ON_ERROR_STOP=1'])
                self.assertNotIn('shell', kwargs); self.assertEqual(kwargs['input'], fixture.SQL.encode())
                self.assertEqual(kwargs['timeout'], 15); self.assertEqual(kwargs['stderr'], subprocess.DEVNULL)
                self.assertIn('"fixture_seeded": true', output.getvalue()); self.assertNotIn('postgres://', output.getvalue())
            files.reset_mock()
            with patch.object(fixture.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)), patch.object(fixture, 'write_files', side_effect=OSError('private path')) as failing, contextlib.redirect_stdout(io.StringIO()) as output:
                with self.assertRaises(RuntimeError) as raised:
                    fixture.main()
                self.assertEqual(failing.call_count, 1); self.assertEqual(output.getvalue(), ''); self.assertNotIn('private path', str(raised.exception))

    def test_optimized_interpreter_keeps_host_guard(self):
        program = r'''
import importlib.util, os, sys
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('fixture',sys.argv[1]); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
with patch.object(module.platform,'system',return_value='Darwin'), patch.object(module.subprocess,'run',side_effect=RuntimeError('unexpected child')):
    try: module.main()
    except RuntimeError as error:
        if str(error)=='Archive fixture requires isolated Linux/aarch64/UID1000':
            print('host refused'); sys.exit(0)
sys.exit(1)
'''
        result = subprocess.run([sys.executable, '-O', '-c', program, str(SOURCE)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0); self.assertEqual(result.stdout.strip(), 'host refused')


if __name__ == '__main__':
    unittest.main()
