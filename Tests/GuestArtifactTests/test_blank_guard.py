"""Exercise only init's disk decision with fake commands, never a real formatter."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BlankGuardTests(unittest.TestCase):
    def test_only_success_can_reach_format_and_faults_keep_distinct_stage(self):
        source = (ROOT / 'guest/backend-init').read_text()
        start = source.index('    echo ARTEX_MAC_STAGE_state_zero_check\n')
        stop = source.index('\nfi\n', start)
        fragment = source[start:stop]
        for status in [0, 2, 1, 3, 137, 139, 143]:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for name, body in [('python3', 'exit "$FIXTURE_STATUS"'),
                                   ('mkfs.ext4', 'printf format > "$FIXTURE_WITNESS"')]:
                    tool = root / name
                    tool.write_text('#!/bin/sh\n' + body + '\n')
                    tool.chmod(0o700)
                env = dict(os.environ, PATH=str(root) + ':/usr/bin:/bin', FIXTURE_STATUS=str(status), FIXTURE_WITNESS=str(root / 'witness'))
                script = 'set -eu\nfail() { printf "FAIL_STAGE=%s\\n" "$1"; exit 91; }\n' + fragment
                result = subprocess.run(['/bin/sh', '-c', script], env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual((root / 'witness').exists(), status == 0)
                if status == 0:
                    self.assertEqual(result.returncode, 0)
                else:
                    self.assertEqual(result.returncode, 91)
                    stage = 'nonblank-state-disk' if status == 2 else 'state-blank-check-failed'
                    self.assertIn('FAIL_STAGE=' + stage, result.stdout)
