"""Independent reference validators must stop on wrong owners, terminal errors and deadlines."""
import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[2] / 'script'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('archive_reference', SCRIPTS / 'task_archive_reference.py')
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


class ArchiveReferenceTests(unittest.TestCase):
    def test_only_expected_archive_identity_and_state_complete(self):
        valid = {'id': 7, 'task_id': 7101, 'state': 'ready'}
        self.assertEqual(reference.poll_archive(lambda: (200, valid), 7, 7101, 'ready', {'archiving'}, sleep=lambda _: None), valid)
        for value in [{**valid, 'task_id': 7102}, {**valid, 'id': 8}, {**valid, 'state': 'archive_failed'}]:
            with self.assertRaises(RuntimeError):
                reference.poll_archive(lambda: (200, value), 7, 7101, 'ready', {'archiving'}, sleep=lambda _: None)
        with self.assertRaises(RuntimeError):
            reference.poll_archive(lambda: (404, {}), 7, 7101, 'ready', {'archiving'}, sleep=lambda _: None)
        self.assertIsNone(reference.poll_archive(lambda: (404, {}), 7, 7101, None, {'restoring'}, sleep=lambda _: None))

    def test_poll_is_finite_and_rejects_completion_after_deadline(self):
        calls = []
        def pending():
            calls.append(1); return 200, {'id': 7, 'task_id': 7101, 'state': 'archiving'}
        with self.assertRaises(RuntimeError):
            reference.poll_archive(pending, 7, 7101, 'ready', {'archiving'}, sleep=lambda _: None, clock=lambda: 0)
        self.assertEqual(len(calls), 120)
        times = iter([0, 0, 46])
        with self.assertRaises(RuntimeError):
            reference.poll_archive(lambda: (200, {'id': 7, 'task_id': 7101, 'state': 'ready'}), 7, 7101, 'ready', set(), clock=lambda: next(times))
