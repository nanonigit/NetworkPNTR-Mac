"""Fault injection is confined to one synthetic guest archive and never overwrites."""
import hashlib
import importlib.util
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / 'script'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('archive_control', SCRIPTS / 'task_archive_fixture_control.py')
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)


class ArchiveControlTests(unittest.TestCase):
    def test_host_refused_before_database_or_files(self):
        with patch.object(control, 'validate_environment', side_effect=RuntimeError('host refused')), patch.object(control, 'query') as query:
            for operation in [lambda: control.audit(), lambda: control.set_package_hidden(True, 7, 'a' * 64)]:
                with self.assertRaises(RuntimeError):
                    operation()
            query.assert_not_called()

    def test_invalid_identity_or_operation_refused_before_query(self):
        with patch.object(control, 'validate_environment', return_value={}), patch.object(control, 'query') as query:
            for hidden, identifier, digest in [(1, 7, 'a' * 64), (True, True, 'a' * 64), (True, 0, 'a' * 64), (True, 2 ** 63, 'a' * 64), (True, 7, 'private'), (True, 7, 'A' * 64)]:
                with self.assertRaises(RuntimeError):
                    control.set_package_hidden(hidden, identifier, digest)
            query.assert_not_called()

    def test_hide_and_repair_preserve_exact_bytes_and_refuse_existing_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); parent = root / 'archives/tasks'; parent.mkdir(parents=True)
            package = parent / 'task-7101-7.tar.zst'; data = b'fixed archive fixture\x00bytes'; package.write_bytes(data)
            digest = hashlib.sha256(data).hexdigest()
            row = {'id': 7, 'task_id': 7101, 'state': 'ready', 'archive_path': str(package), 'sha256': digest, 'task_name': control.NAME, 'task_goal': control.GOAL}
            with patch.object(control, 'DATA_ROOT', root), patch.object(control, 'validate_environment', return_value={}), patch.object(control, 'query', side_effect=lambda *args: dict(row)):
                hidden = control.set_package_hidden(True, 7, digest)
                self.assertEqual(hidden['operation'], 'hide'); self.assertFalse(package.exists())
                backup = parent / 'task-7101-7.tar.zst.t17-quarantine'; self.assertEqual(backup.read_bytes(), data)
                row['state'] = 'restore_failed'; package.write_bytes(b'keep')
                with self.assertRaises(RuntimeError):
                    control.set_package_hidden(False, 7, digest)
                self.assertEqual(package.read_bytes(), b'keep'); self.assertEqual(backup.read_bytes(), data)
                package.unlink(); repaired = control.set_package_hidden(False, 7, digest)
                self.assertEqual(repaired['operation'], 'repair'); self.assertFalse(backup.exists()); self.assertEqual(package.read_bytes(), data)

    def test_foreign_owner_name_state_hash_path_or_symlink_never_moves(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); parent = root / 'archives/tasks'; parent.mkdir(parents=True)
            package = parent / 'task-7101-7.tar.zst'; package.write_bytes(b'fixed')
            digest = hashlib.sha256(b'fixed').hexdigest()
            row = {'id': 7, 'task_id': 7101, 'state': 'ready', 'archive_path': str(package), 'sha256': digest, 'task_name': control.NAME, 'task_goal': control.GOAL}
            for key, value in [('id', 8), ('task_id', 7102), ('task_name', 'different'), ('state', 'restoring'), ('sha256', 'b' * 64), ('archive_path', '/etc/private')]:
                with self.subTest(field=key), patch.object(control, 'DATA_ROOT', root), patch.object(control, 'validate_environment', return_value={}), patch.object(control, 'query', return_value={**row, key: value}):
                    with self.assertRaises(RuntimeError):
                        control.set_package_hidden(True, 7, digest)
                    self.assertEqual(package.read_bytes(), b'fixed')
            outside = root / 'outside'; outside.write_bytes(b'fixed'); package.unlink(); package.symlink_to(outside)
            with patch.object(control, 'DATA_ROOT', root), patch.object(control, 'validate_environment', return_value={}), patch.object(control, 'query', return_value=row):
                with self.assertRaises(RuntimeError):
                    control.set_package_hidden(True, 7, digest)
            self.assertEqual(outside.read_bytes(), b'fixed')

    def test_audit_requires_all_typed_zero_counts(self):
        zeros = {key: 0 for key in control.AUDIT_KEYS}
        with patch.object(control, 'validate_environment', return_value={}), patch.object(control, 'query', return_value=zeros):
            self.assertTrue(control.audit()['fixture_audit'])
        for value in [{}, {**zeros, 'activity': 1}, {**zeros, 'llm_usage': False}, {**zeros, 'profiles': '0'}]:
            with patch.object(control, 'validate_environment', return_value={}), patch.object(control, 'query', return_value=value):
                with self.assertRaises(RuntimeError):
                    control.audit()

    def test_changed_bytes_or_oversized_package_never_moves(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); parent = root / 'archives/tasks'; parent.mkdir(parents=True)
            package = parent / 'task-7101-7.tar.zst'; digest = hashlib.sha256(b'expected').hexdigest()
            row = {'id': 7, 'task_id': 7101, 'state': 'ready', 'archive_path': str(package), 'sha256': digest, 'task_name': control.NAME, 'task_goal': control.GOAL}
            for size in [7, 8 * 1024 * 1024 + 1]:
                with package.open('wb') as stream:
                    stream.write(b'changed'); stream.truncate(size)
                with patch.object(control, 'DATA_ROOT', root), patch.object(control, 'validate_environment', return_value={}), patch.object(control, 'query', return_value=row):
                    with self.assertRaises(RuntimeError):
                        control.set_package_hidden(True, 7, digest)
                self.assertTrue(package.is_file()); self.assertEqual(package.stat().st_size, size)
                self.assertFalse(package.with_name(package.name + '.t17-quarantine').exists())

    def test_query_failure_is_bounded_and_does_not_expose_child_output(self):
        for result in [subprocess.CompletedProcess([], 1, b'private password'), subprocess.CompletedProcess([], 0, b'x' * 8193),
                       subprocess.CompletedProcess([], 0, b'not-json private'), subprocess.CompletedProcess([], 0, b'[]')]:
            with patch.object(control.subprocess, 'run', return_value=result) as run:
                with self.assertRaises(RuntimeError) as failure:
                    control.query({'PGPASSWORD': 'secret'}, 'fixed SQL')
                self.assertNotIn('private', str(failure.exception)); self.assertNotIn('secret', str(failure.exception))
                self.assertEqual(run.call_args.kwargs['timeout'], 15); self.assertEqual(run.call_args.kwargs['stderr'], subprocess.DEVNULL)
        with patch.object(control.subprocess, 'run', side_effect=subprocess.TimeoutExpired('psql', 15)):
            with self.assertRaises(RuntimeError):
                control.query({}, 'fixed SQL')

    def test_non_regular_package_is_refused_without_blocking(self):
        program = """import sys
from pathlib import Path
sys.path.insert(0,sys.argv[1])
import task_archive_fixture_control as c
try: c.package_digest(Path(sys.argv[2]))
except RuntimeError: print('nonregular refused');sys.exit(0)
sys.exit(1)
"""
        with tempfile.TemporaryDirectory() as directory:
            fifo = Path(directory) / 'fixture-fifo'; os.mkfifo(fifo)
            result = subprocess.run([sys.executable, '-c', program, str(SCRIPTS), str(fifo)], capture_output=True, text=True, timeout=2)
            self.assertEqual(result.returncode, 0); self.assertEqual(result.stdout.strip(), 'nonregular refused')


if __name__ == '__main__':
    unittest.main()
