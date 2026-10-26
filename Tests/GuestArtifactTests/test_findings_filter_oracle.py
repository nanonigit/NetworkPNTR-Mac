"""The browser oracle executes only the exact checksum-pinned filter function."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('findings_filter_oracle', ROOT / 'script/findings_filter_oracle.py')
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)


class FindingFilterOracleTests(unittest.TestCase):
    def test_source_mismatch_refused_before_any_node_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'api.ts'; source.write_text('throw new Error("must never run")')
            with patch.object(oracle.subprocess, 'run') as run:
                with self.assertRaises(RuntimeError):
                    oracle.execute(source, [])
                run.assert_not_called()

    def test_checked_in_cases_match_the_pinned_function_when_baseline_is_available(self):
        source = ROOT.parent / 'artex-local/source/web/src/lib/api.ts'
        if not source.exists():
            self.skipTest('Pinned local baseline is a hardware/development comparison gate, not copied into CI')
        import json
        fixture = json.loads((ROOT / 'Tests/ArtexCoreTests/Fixtures/findings-browser-filters.json').read_text())
        self.assertEqual(oracle.execute(source, fixture['cases']), fixture['cases'])
