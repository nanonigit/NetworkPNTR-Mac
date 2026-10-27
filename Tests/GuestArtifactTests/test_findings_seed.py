"""Fixed diagnostic findings must never become a host or arbitrary SQL interface."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / 'script' / 'findings_seed_guest.py'
spec = importlib.util.spec_from_file_location('findings_seed', SOURCE)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
ENV = {'ARTEX_FINDINGS_FIXTURE': '1', 'ARTEX_PG_DSN': 'postgres://artex:' + 'b' * 64 + '@127.0.0.1:5432/artex?sslmode=disable'}


class FindingsSeedTests(unittest.TestCase):
    def validate(self, env=None, system='Linux', machine='aarch64', uid=1000):
        with patch.dict(os.environ, ENV if env is None else env, clear=True), patch.object(fixture.platform, 'system', return_value=system), patch.object(fixture.platform, 'machine', return_value=machine), patch.object(fixture.os, 'getuid', return_value=uid):
            return fixture.validate_environment()

    def test_fixed_dataset_covers_page_groups_statuses_assets_and_distinct_node_handles(self):
        self.assertEqual(fixture.TASK_IDS, tuple(range(8101, 8112)))
        rows = fixture.ROWS
        self.assertEqual([row['id'] for row in rows], list(range(9101, 9134)))
        self.assertEqual(sum(row['task_id'] == 8101 for row in rows), 21)
        self.assertEqual(sum(row['task_id'] is None for row in rows), 2)
        self.assertEqual(len({row['task_id'] for row in rows}), 12)
        self.assertEqual({row['severity'] for row in rows}, {'critical', 'high', 'medium', 'low'})
        self.assertEqual({row['status'] for row in rows}, {'pending', 'in_progress', 'confirmed', 'resolved', 'fixed', 'false_positive', 'ignored', 'duplicate', 'risk_accepted'})
        self.assertEqual(len({row['vulnclass'] for row in rows}), 3)
        self.assertEqual([row['node_id'] for row in rows if row['node_id']], list(range(15101, 15132)))
        self.assertTrue(all(row['node_id'] != row['id'] for row in rows))
        self.assertEqual(fixture.LEGACY_NODE_ID, 15190)
        self.assertTrue(any(not row['asset_ids'] for row in rows)); self.assertTrue(any(len(row['asset_ids']) > 1 for row in rows))
        self.assertTrue(all(set(row['asset_ids']) <= {8201, 8202, 8203} for row in rows))
        self.assertIn('\ufeff', rows[0]['name']); self.assertIn('e\u0301', rows[0]['name']); self.assertIn("'", rows[0]['name'])
        self.assertIn('中文 한국어', rows[0]['name']); self.assertEqual(len({row['ts'] for row in rows}), 33)

    def test_host_arch_uid_marker_refuse_before_child(self):
        for kwargs in [{'system': 'Darwin'}, {'machine': 'x86_64'}, {'uid': 0}, {'env': {**ENV, 'ARTEX_FINDINGS_FIXTURE': '0'}}]:
            with self.subTest(kwargs=kwargs), patch.object(fixture.subprocess, 'run') as child:
                with self.assertRaises(RuntimeError): self.validate(**kwargs)
                child.assert_not_called()

    def test_dsn_requires_exact_loopback_and_cannot_disclose_credentials(self):
        good = ENV['ARTEX_PG_DSN']
        bad = ['', good.replace('127.0.0.1', 'outside.invalid'), good.replace('127.0.0.1', 'localhost'), good.replace(':5432', ':5433'), good.replace(':5432', ':bad'), good.replace('/artex?', '/postgres?'), good.replace('artex:', 'root:'), good.replace('b' * 64, 'private-value'), good + '&options=unsafe', good + '#fragment', good + '&sslmode=disable', good.replace('sslmode=disable', 'sslmode=require')]
        for index, dsn in enumerate(bad):
            with self.subTest(case=index):
                with self.assertRaises(RuntimeError) as raised: self.validate(env={**ENV, 'ARTEX_PG_DSN': dsn})
                self.assertNotIn(dsn or 'never-present', str(raised.exception)); self.assertNotIn('b' * 64, str(raised.exception))

    def test_child_environment_is_an_allowlist_and_sql_ignores_environment(self):
        before = fixture.SQL
        env = self.validate(env={**ENV, 'PGHOSTADDR': 'outside.invalid', 'PGOPTIONS': 'unsafe', 'PGSERVICEFILE': 'private', 'PATH': '/unsafe', 'HOME': '/private'})
        self.assertEqual(set(env), {'PATH', 'PGHOST', 'PGPORT', 'PGDATABASE', 'PGUSER', 'PGPASSWORD', 'PGCONNECT_TIMEOUT', 'PGCLIENTENCODING'})
        self.assertEqual(env['PGHOST'], '127.0.0.1'); self.assertNotEqual(env['PATH'], '/unsafe'); self.assertEqual(fixture.SQL, before)

    def test_sql_is_one_transaction_with_fresh_state_locks_and_postconditions(self):
        sql = fixture.SQL
        self.assertTrue(sql.lstrip().startswith('BEGIN;')); self.assertTrue(sql.rstrip().endswith('COMMIT;'))
        self.assertIn("lock_timeout = '2s'", sql); self.assertIn("statement_timeout = '5s'", sql)
        for table in ['tasks', 'explorations', 'exploration_nodes', 'findings', 'companies', 'assets', 'task_relations', 'llm_profiles', 'llm_records', 'llm_usage', 'activity', 'conversations', 'task_archives', 'finding_retests', 'finding_traffic_bindings']:
            self.assertIn('SELECT 1 FROM ' + table, sql)
        self.assertLess(sql.index('LOCK TABLE'), sql.index('INSERT INTO'))
        self.assertIn('count(*) FROM findings) <> 33', sql); self.assertIn('count(*) FROM tasks) <> 11', sql)
        self.assertIn('INSERT INTO task_relations', sql); self.assertIn('(8111,8101)', sql)
        self.assertNotIn('DELETE FROM', sql); self.assertNotIn('TRUNCATE', sql); self.assertNotIn('DROP ', sql)
        self.assertNotIn('INSERT INTO activity', sql); self.assertNotIn('INSERT INTO llm_profiles', sql)
        self.assertIn("''quoted''", sql)

    def test_failures_timeout_or_launch_error_emit_no_proof_and_no_retry(self):
        for result in [subprocess.CompletedProcess([], 1), subprocess.TimeoutExpired(['private-dsn'], 15), OSError('private path')]:
            with self.subTest(kind=type(result).__name__), patch.object(fixture, 'validate_environment', return_value={'PATH': '/safe'}):
                options = {'side_effect': result} if isinstance(result, Exception) else {'return_value': result}
                with patch.object(fixture.subprocess, 'run', **options) as child, contextlib.redirect_stdout(io.StringIO()) as output:
                    with self.assertRaises(RuntimeError) as raised: fixture.main()
                    self.assertEqual(child.call_count, 1); self.assertEqual(output.getvalue(), '')
                    self.assertNotIn('private', str(raised.exception))

    def test_success_emits_only_fixed_manifest_after_sanitized_psql(self):
        with patch.object(fixture, 'validate_environment', return_value={'PATH': '/safe'}), patch.object(fixture.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as child, contextlib.redirect_stdout(io.StringIO()) as output:
            fixture.main(); args, kwargs = child.call_args
            self.assertEqual(args[0], ['psql', '-X', '--no-password', '-q', '-v', 'ON_ERROR_STOP=1'])
            self.assertEqual(kwargs['input'], fixture.SQL.encode()); self.assertEqual(kwargs['timeout'], 15)
            self.assertEqual(kwargs['stdout'], subprocess.DEVNULL); self.assertEqual(kwargs['stderr'], subprocess.DEVNULL); self.assertNotIn('shell', kwargs)
            proof = json.loads(output.getvalue()); self.assertTrue(proof['fixture_seeded'])
            self.assertEqual(proof['task_ids'], list(fixture.TASK_IDS)); self.assertEqual(proof['finding_ids'], list(range(9101, 9134)))
            self.assertNotIn('postgres', output.getvalue()); self.assertNotIn('password', output.getvalue())

    def test_optimized_host_execution_still_refuses_before_database(self):
        env = {**os.environ, **ENV}
        result = subprocess.run([sys.executable, '-O', str(SOURCE)], env=env, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0); self.assertEqual(result.stdout, b'')
        self.assertNotIn(b'b' * 64, result.stderr); self.assertNotIn(b'postgres://', result.stderr)

    def test_sequence_updates_are_transactional_when_later_postconditions_fail(self):
        self.assertNotIn('setval(', fixture.SQL)
        for table, next_id in [('tasks', 8112), ('explorations', 8112), ('companies', 8201), ('assets', 8204), ('findings', 9134), ('exploration_nodes', 15191)]:
            self.assertIn(f'ALTER SEQUENCE {table}_id_seq RESTART WITH {next_id};', fixture.SQL)


if __name__ == '__main__': unittest.main()
