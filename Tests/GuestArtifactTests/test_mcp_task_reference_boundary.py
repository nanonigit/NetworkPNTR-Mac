"""Local-only reference containment and cleanup remain enforced on harness failure."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'script/verify_mcp_task_fixture.py'
spec = importlib.util.spec_from_file_location('mcp_task_reference', SOURCE)
fixture = importlib.util.module_from_spec(spec)
original = sys.path[:]
try:
    sys.path.insert(0, str(SOURCE.parent))
    spec.loader.exec_module(fixture)
finally:
    sys.path[:] = original


class MCPTaskReferenceBoundaryTests(unittest.TestCase):
    def test_docker_calls_always_use_explicit_local_context_and_scrubbed_environment(self):
        with patch.object(fixture.subprocess, 'run') as child:
            fixture.docker_run(['docker', 'version'])
        args, kwargs = child.call_args
        self.assertEqual(args[0], ['/usr/local/bin/docker', '--context', 'desktop-linux', 'version'])
        self.assertFalse(any(k.startswith(('DOCKER_', 'BUILDKIT_')) for k in kwargs['env']))

    def test_first_cleanup_timeout_does_not_skip_remaining_owned_resources(self):
        calls = []
        def child(args, **kwargs):
            calls.append(args)
            if args == ['docker', 'rm', '-f', 'app']:
                raise subprocess.TimeoutExpired(args, 30)
            inspect = args[1] == 'inspect' or args[1:3] == ['network', 'inspect']
            return subprocess.CompletedProcess(args, 0, stdout='owner\n' if inspect else '', stderr='')
        with patch.object(fixture, 'docker_run', side_effect=child):
            result = fixture.cleanup_owned('owner', 'net', ['app', 'db'])
        self.assertFalse(result['verified'])
        self.assertEqual(result['issues'][0]['errorType'], 'TimeoutExpired')
        self.assertIn(['docker', 'rm', '-f', 'db'], calls)
        self.assertIn(['docker', 'network', 'rm', 'net'], calls)
        self.assertTrue(any(c[1] == 'ps' for c in calls))
        self.assertTrue(any(c[1:3] == ['network', 'ls'] for c in calls))

    def test_unowned_resources_are_never_removed(self):
        with patch.object(fixture, 'docker_run', side_effect=lambda args, **kw: subprocess.CompletedProcess(args, 0, stdout='other' if 'inspect' in args else '', stderr='')) as child:
            result = fixture.cleanup_owned('owner', 'net', ['app', 'db'])
        self.assertTrue(result['verified'])
        self.assertTrue(all('rm' not in call.args[0] for call in child.call_args_list))

    def test_receipt_write_failure_does_not_mask_primary_preflight_failure(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(fixture, 'docker_run', side_effect=lambda args, **kw: subprocess.CompletedProcess(args, 0, stdout='tcp://remote.invalid:2376', stderr='')), patch.object(Path, 'write_text', side_effect=OSError('private-write-error')):
            with self.assertRaisesRegex(RuntimeError, 'local_cached_preflight'):
                fixture.verify(Path(directory)/'new')

    def test_remote_context_is_rejected_before_creation(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(fixture, 'docker_run', side_effect=lambda args, **kw: subprocess.CompletedProcess(args, 0, stdout='tcp://remote.invalid:2376', stderr='')) as child:
            with self.assertRaisesRegex(RuntimeError, 'local_cached_preflight'):
                fixture.verify(Path(directory)/'new')
        self.assertTrue(all('run' not in call.args[0] and 'create' not in call.args[0] for call in child.call_args_list))
