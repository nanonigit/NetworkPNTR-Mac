import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
from disposable_reference_cleanup import cleanup_reference


class DisposableReferenceCleanupTests(unittest.TestCase):
    docker = ['docker', '--context', 'desktop-linux']
    containers = ['a' * 64, 'b' * 64]
    network = 'c' * 64

    def exercise(self, fault):
        calls = []

        def run(args, **kwargs):
            command = args[len(self.docker):]
            calls.append(command)
            if command[0] == 'logs' and fault == 'logs_timeout':
                raise subprocess.TimeoutExpired(args, 20)
            if command[:2] == ['rm', '--force'] and command[-1] == self.containers[1] and fault == 'remove_timeout':
                raise subprocess.TimeoutExpired(args, 30)
            return SimpleNamespace(returncode=0, stdout=b'private diagnostic', stderr=b'')

        with tempfile.TemporaryDirectory() as directory:
            result = cleanup_reference(self.docker, self.containers, self.network, Path(directory), run=run)
        return result, calls

    def test_log_timeout_never_skips_any_removal(self):
        result, calls = self.exercise('logs_timeout')
        self.assertTrue(result['cleanup'])
        self.assertFalse(result['logs_complete'])
        self.assertIn(['rm', '--force', self.containers[0]], calls)
        self.assertIn(['rm', '--force', self.containers[1]], calls)
        self.assertIn(['network', 'rm', self.network], calls)

    def test_first_removal_timeout_still_attempts_remaining_container_and_network(self):
        result, calls = self.exercise('remove_timeout')
        self.assertFalse(result['cleanup'])
        self.assertIn(['rm', '--force', self.containers[0]], calls)
        self.assertIn(['network', 'rm', self.network], calls)
        self.assertIn('container_remove_unconfirmed', result['errors'])
        self.assertNotIn('private diagnostic', json.dumps(result))

    def test_invalid_owned_identity_never_reaches_subprocess(self):
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            result = cleanup_reference(self.docker, ['--all'], self.network, Path(directory),
                                       run=lambda *args, **kwargs: calls.append(args))
        self.assertFalse(result['cleanup'])
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
