"""Independent reference validators must stop on wrong owners, terminal errors and deadlines."""
import importlib.util
from pathlib import Path
import sys
import unittest
import subprocess
from unittest.mock import patch, Mock

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

    def test_raw_archive_fields_and_active_owner_are_checked(self):
        row = {'task_id': 7101, 'state': 'ready', 'progress': 100, 'original_status': 'done', 'error': '', 'warnings': [],
               'original_size': 100, 'compressed_size': 50, 'sha256': 'a' * 64, 'data_counts': {'tasks': 1, 'explorations': 1},
               'category_id': 7100, 'category_name': 'T17 archive category', 'task_name': reference.seed.NAME,
               'task_description': reference.seed.DESCRIPTION, 'task_goal': reference.seed.GOAL}
        reference.ready(row, 7101)
        for changed in [{**row, 'error': 'failure'}, {**row, 'warnings': ['warning']}]:
            with self.assertRaises(RuntimeError):
                reference.ready(changed, 7101)
        class ForeignActive:
            def api(self, *args):
                return {'tasks': [], 'active': '9999'}
        with self.assertRaises(RuntimeError):
            reference.live(ForeignActive(), set())

    def test_late_live_response_cannot_complete(self):
        class Empty:
            def api(self, *args):
                return {'tasks': [], 'active': ''}
        times = iter([0, 0, 46])
        with patch.object(reference.time, 'monotonic', side_effect=lambda: next(times)):
            with self.assertRaises(RuntimeError):
                reference.live(Empty(), set())

    def test_process_failure_and_stop_timeout_never_report_success(self):
        class API:
            token = None
            def request(self, method, path):
                return (200, {'initialized': False, 'setup_token_required': True}) if path == '/api/auth/status' else (401, {})
            def api(self, *args):
                return {'token': 'fixture-only'}
        for mode in ['launch', 'dead', 'stop_timeout']:
            with self.subTest(mode=mode), patch.object(reference.platform, 'system', return_value='Linux'), patch.object(reference.os, 'getuid', return_value=1000), patch.dict(reference.os.environ, {'ARTEX_DISPOSABLE_REFERENCE': '1'}), patch.object(reference.seed, 'validate_environment'), patch.object(reference.seed, 'main'), patch.object(reference.control, 'audit'), patch.object(reference, 'Client', API), patch.object(reference.Path, 'open', return_value=Mock(__enter__=Mock(return_value=Mock()), __exit__=Mock(return_value=False))):
                process = Mock(); process.poll.return_value = 1 if mode == 'dead' else None
                if mode == 'stop_timeout':
                    process.wait.side_effect = [subprocess.TimeoutExpired('fixture', 20), subprocess.TimeoutExpired('fixture', 10), -9]
                with patch.object(reference.subprocess, 'Popen', side_effect=OSError('launch failed') if mode == 'launch' else None, return_value=process), patch('builtins.print') as output:
                    with self.assertRaises((OSError, RuntimeError, subprocess.TimeoutExpired)):
                        reference.main()
                    output.assert_not_called()
                if mode == 'stop_timeout':
                    process.kill.assert_called_once(); self.assertEqual(process.wait.call_count, 3)

    def test_empty_page_accepts_explicit_null_but_requires_items_key(self):
        class API:
            def __init__(self, page):
                self.page = page
            def api(self, *args):
                return self.page
        value = {'page': 1, 'size': 20, 'total': 0, 'items': None}
        self.assertEqual(reference.page(API(value), 0), [])
        for bad in [{'page': 1, 'size': 20, 'total': 0}, {**value, 'total': 1}, {**value, 'items': {}}]:
            with self.assertRaises(RuntimeError):
                reference.page(API(bad), 0)
