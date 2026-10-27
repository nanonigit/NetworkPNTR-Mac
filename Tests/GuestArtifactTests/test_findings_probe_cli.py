"""A malformed probe invocation must not boot a VM or overwrite existing output."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FindingsProbeCLITests(unittest.TestCase):
    def test_existing_output_and_wrong_arity_refused_before_boot(self):
        folder = subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=ROOT, text=True, timeout=45).strip().splitlines()[-1]
        probe = Path(folder) / 'VMProbe'
        self.assertTrue(probe.is_file())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); output = root / 'existing'; output.mkdir()
            sentinel = output / 'keep.txt'; sentinel.write_text('untouched')
            result = subprocess.run([str(probe), '--findings', 'not-loaded', str(output)], cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertIn('findings_stage=preparing boot_attempts=0', result.stderr)
            self.assertEqual(sentinel.read_text(), 'untouched')
            self.assertEqual(sorted(p.name for p in output.iterdir()), ['keep.txt'])
            invalid = subprocess.run([str(probe), '--findings', 'one-argument'], cwd=root, capture_output=True, text=True, timeout=10)
            self.assertEqual(invalid.returncode, 2); self.assertIn('NEW_PRIVATE_OUTPUT', invalid.stderr)


if __name__ == '__main__':
    unittest.main()
