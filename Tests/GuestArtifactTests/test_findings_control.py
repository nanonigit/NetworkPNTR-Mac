"""Fixed audit boundaries; synthetic query replies do not establish guest/runtime acceptance."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'script'))
SPEC = importlib.util.spec_from_file_location('findings_fixture_control', ROOT / 'script/findings_fixture_control.py')
control = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(control)


class FindingsControlTests(unittest.TestCase):
    def counts(self, fresh=False, persisted=False):
        values = {key: 0 for key in control.ZERO_KEYS}
        values.update(tasks=0 if fresh else 11, explorations=0 if fresh else 11,
                      relations=0 if fresh else 1, companies=0 if fresh else 1, assets=0 if fresh else 3,
                      findings=0 if fresh else (31 if persisted else 33),
                      finding_nodes=0 if fresh else (31 if persisted else 32), events=3 if persisted else 0)
        return values

    def test_host_and_invalid_phase_refused_before_query(self):
        with patch.object(control, 'validate_environment', side_effect=RuntimeError('host refused')), patch.object(control, '_query') as query:
            with self.assertRaises(RuntimeError):
                control.audit()
            query.assert_not_called()
        with patch.object(control, 'validate_environment', return_value={}), patch.object(control, '_query') as query:
            for phase in [1, None, 'fresh', {}, []]:
                with self.assertRaises(RuntimeError):
                    control.audit(fresh=phase)
            query.assert_not_called()

    def test_exact_fresh_initial_and_persisted_snapshots_only(self):
        with patch.object(control, 'validate_environment', return_value={}), patch.object(control.os, 'getuid', return_value=1000):
            for fresh, persisted in [(True, False), (False, False), (False, True)]:
                values = self.counts(fresh, persisted)
                with patch.object(control, '_query', return_value=values):
                    proof = control.audit(fresh=fresh)
                self.assertEqual(proof, {'fixture_audit': True, 'uid': 1000, 'fresh': fresh, 'counts': values})

    def test_every_zero_guard_and_shape_or_type_error_rejected(self):
        original = self.counts()
        variants = []
        for key in control.ZERO_KEYS:
            value = dict(original); value[key] = 1; variants.append(value)
        for invalid in [True, -1, 1.0, '0', None]:
            value = dict(original); value['activity'] = invalid; variants.append(value)
        missing = dict(original); missing.pop('foreign_tasks'); variants += [missing, dict(original, extra=0)]
        with patch.object(control, 'validate_environment', return_value={}), patch.object(control.os, 'getuid', return_value=1000):
            for value in variants:
                with patch.object(control, '_query', return_value=value), self.assertRaises(RuntimeError):
                    control.audit()

    def test_wrong_owned_counts_partial_delete_and_foreign_events_rejected(self):
        variants = []
        original = self.counts()
        for key in ['tasks', 'explorations', 'relations', 'companies', 'assets', 'findings', 'finding_nodes', 'events']:
            changed = dict(original); changed[key] = 99; variants.append(changed)
        changed = dict(original); changed['findings'] = 31; variants.append(changed)
        changed = dict(original); changed['finding_nodes'] = 31; variants.append(changed)
        changed = self.counts(fresh=True); changed['events'] = 1; variants.append((changed, True))
        variants += [(self.counts(), True), (self.counts(fresh=True), False)]
        with patch.object(control, 'validate_environment', return_value={}):
            for variant in variants:
                value, fresh = variant if isinstance(variant, tuple) else (variant, False)
                with patch.object(control, '_query', return_value=value), self.assertRaises(RuntimeError):
                    control.audit(fresh=fresh)

    def test_bounded_fixed_query_uses_sanitized_environment_and_never_returns_stderr(self):
        environment = {'PGHOST': '127.0.0.1', 'PGPASSWORD': 'private-fixture-password'}
        reply = SimpleNamespace(returncode=0, stdout=json.dumps(self.counts()).encode())
        with patch.object(control.subprocess, 'run', return_value=reply) as run:
            self.assertEqual(control._query(environment), self.counts())
        args, kwargs = run.call_args
        self.assertEqual(args[0], ['psql', '-X', '--no-password', '-Aqt', '-v', 'ON_ERROR_STOP=1', '-c', control.AUDIT_SQL])
        self.assertEqual(kwargs['env'], environment); self.assertEqual(kwargs['timeout'], 15)
        self.assertEqual(kwargs['stderr'], subprocess.DEVNULL)
        self.assertNotIn('private-fixture-password', ' '.join(args[0]))
        self.assertIn("statement_timeout = '5s'", control.AUDIT_SQL)
        for fragment in ['task_llm_profiles', 'notification_channels', 'notification_deliveries', 'foreign_events', 'finding_retests', 'traffic_evidence_snapshots']:
            self.assertIn(fragment, control.AUDIT_SQL)

    def test_query_child_errors_oversize_and_non_object_reply_are_sanitized(self):
        for failure in [OSError('private'), subprocess.TimeoutExpired('private', 15)]:
            with patch.object(control.subprocess, 'run', side_effect=failure), self.assertRaises(RuntimeError) as error:
                control._query({})
            self.assertNotIn('private', str(error.exception))
        for code, output in [(1, b'private'), (0, b'private'), (0, b'[]'), (0, b' ' * 8193)]:
            with patch.object(control.subprocess, 'run', return_value=SimpleNamespace(returncode=code, stdout=output)), self.assertRaises(RuntimeError):
                control._query({})


if __name__ == '__main__':
    unittest.main()
