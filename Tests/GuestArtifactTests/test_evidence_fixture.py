"""Diagnostic bodies must be deterministic and never escape their owned guest root."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import types
from unittest.mock import Mock
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / 'script/evidence_fixture_guest.py'
SPEC = importlib.util.spec_from_file_location('evidence_fixture_guest', SCRIPT)
FIXTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURE)


class EvidenceFixtureTests(unittest.TestCase):
    def test_fixed_body_shapes_and_bounded_binary_generator(self):
        bodies = FIXTURE.body_manifest()
        self.assertEqual(list(bodies), ['literal', 'binary', 'empty', 'large'])
        self.assertEqual([row['size'] for row in bodies.values()][1:], [5 * 1024 * 1024 + 17, 0, 129 * 1024 * 1024 + 17])
        for name, expected in bodies.items():
            digest, count = hashlib.sha256(), 0
            for chunk in FIXTURE.body_chunks(name):
                self.assertLessEqual(len(chunk), 65536)
                digest.update(chunk)
                count += len(chunk)
            self.assertEqual(count, expected['size'])
            self.assertEqual(digest.hexdigest(), expected['sha256'])
        literal = b''.join(FIXTURE.body_chunks('literal'))
        self.assertTrue(literal.startswith(b'\xef\xbb\xbf'))
        self.assertIn('e\u0301'.encode(), literal)
        self.assertIn('\u4e2d\u6587'.encode(), literal)
        self.assertIn('\ud55c\uad6d\uc5b4'.encode(), literal)
        with self.assertRaises(RuntimeError):
            list(FIXTURE.body_chunks('../outside'))

    def test_actual_blob_files_match_and_have_private_permissions(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(FIXTURE, 'ROOT', Path(directory) / 'evidence'):
            proof = FIXTURE.write_bodies()
            self.assertEqual(proof, FIXTURE.body_manifest())
            FIXTURE.audit_bodies()
            for row in proof.values():
                path = FIXTURE.ROOT / 'blobs' / row['sha256'][:2] / (row['sha256'] + '.bin')
                self.assertEqual(path.stat().st_size, row['size'])
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
                self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
            with self.assertRaises(RuntimeError):
                FIXTURE.write_bodies()
            FIXTURE.audit_bodies()

    def test_symlink_root_prefix_and_existing_body_are_never_followed_or_replaced(self):
        for kind in ('root', 'prefix', 'body'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                base = Path(directory); root = base / 'evidence'; outside = base / 'outside'; outside.mkdir()
                row = FIXTURE.body_manifest()['literal']; digest = row['sha256']
                target = outside / 'keep.bin'; target.write_bytes(b'keep')
                if kind == 'root':
                    root.symlink_to(outside, target_is_directory=True)
                else:
                    (root / 'blobs').mkdir(parents=True, mode=0o700)
                    if kind == 'prefix':
                        (root / 'blobs' / digest[:2]).symlink_to(outside, target_is_directory=True)
                    else:
                        prefix = root / 'blobs' / digest[:2]; prefix.mkdir(mode=0o700)
                        (prefix / (digest + '.bin')).symlink_to(target)
                with patch.object(FIXTURE, 'ROOT', root), self.assertRaises(RuntimeError):
                    FIXTURE.write_bodies()
                self.assertEqual(target.read_bytes(), b'keep')
                self.assertEqual(sorted(p.name for p in outside.iterdir()), ['keep.bin'])

    def test_stream_audit_detects_same_length_corruption_truncation_and_symlink(self):
        for kind in ('corrupt', 'short', 'link'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory, patch.object(FIXTURE, 'ROOT', Path(directory) / 'evidence'):
                proof = FIXTURE.write_bodies(); row = proof['literal']
                path = FIXTURE.ROOT / 'blobs' / row['sha256'][:2] / (row['sha256'] + '.bin')
                if kind == 'corrupt': path.write_bytes(b'x' * row['size'])
                elif kind == 'short': path.write_bytes(b'x')
                else:
                    path.unlink(); target = Path(directory) / 'target'; target.write_bytes(b'keep'); path.symlink_to(target)
                with self.assertRaises(RuntimeError): FIXTURE.audit_bodies()

    def test_foreign_owner_and_non_directory_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'evidence'; root.mkdir()
            with patch.object(FIXTURE, 'ROOT', root), patch.object(FIXTURE.os, 'getuid', return_value=-1), self.assertRaises(RuntimeError):
                FIXTURE.write_bodies()
            root.rmdir(); root.write_bytes(b'keep')
            with patch.object(FIXTURE, 'ROOT', root), self.assertRaises(RuntimeError): FIXTURE.write_bodies()
            self.assertEqual(root.read_bytes(), b'keep')

    def test_snapshot_identity_matches_frozen_go_field_order_and_sql_is_guarded(self):
        rows = FIXTURE.snapshots()
        self.assertEqual(len(rows), 2)
        self.assertEqual([row['source_traffic_id'] for row in rows], ['f5-fixed-binary', 'f5-fixed-large'])
        for row in rows:
            original = dict(row); original['id'] = ''; original['created_at'] = '0001-01-01T00:00:00Z'
            raw = json.dumps(original, ensure_ascii=False, separators=(',', ':')).encode()
            self.assertEqual(row['id'], hashlib.sha256(raw).hexdigest())
        sql = FIXTURE.fixture_sql()
        for text in ("BEGIN;", "SET LOCAL lock_timeout", "SET LOCAL statement_timeout", "LOCK TABLE", "fresh evidence fixture required", "INSERT INTO traffic_evidence_snapshots", "INSERT INTO finding_traffic_bindings", "UPDATE findings SET evidence_version=1", "COMMIT;"):
            self.assertIn(text, sql)
        self.assertNotIn('DROP ', sql.upper())
        self.assertNotIn('TRUNCATE ', sql.upper())

    def test_non_guest_prepare_and_audit_fail_before_database_or_file_work(self):
        for action in (FIXTURE.prepare, FIXTURE.audit):
            with patch.object(FIXTURE, 'guest_environment', side_effect=RuntimeError('guest only')), patch.object(FIXTURE, 'write_bodies') as files, patch.object(FIXTURE, 'run_sql') as sql:
                with self.assertRaises(RuntimeError): action()
                files.assert_not_called(); sql.assert_not_called()

    def test_postgres_failure_and_excess_output_are_never_accepted_as_proof(self):
        environment = {'PGHOST': '127.0.0.1'}
        with patch.object(FIXTURE.subprocess, 'run', side_effect=OSError('no process')):
            with self.assertRaises(RuntimeError): FIXTURE.run_sql(environment, 'fixed')
        for code, output in [(1, b''), (0, b'x' * 65537), (0, b'not json')]:
            response = type('Reply', (), {'returncode': code, 'stdout': output})()
            with patch.object(FIXTURE.subprocess, 'run', return_value=response):
                with self.assertRaises(RuntimeError): FIXTURE.run_sql(environment, 'fixed', proof=True)

    def _audit_control(self):
        zero = ('foreign_tasks', 'unsafe_tasks', 'profiles', 'activity', 'traffic_bindings', 'traffic_snapshots')
        owned = ('tasks', 'explorations', 'relations', 'companies', 'assets', 'findings', 'finding_nodes', 'events')
        counts = dict(zip(owned, (11, 11, 1, 1, 3, 33, 32, 0)))
        counts.update({key: 0 for key in zero})
        counts.update(traffic_bindings=2, traffic_snapshots=2)
        control = types.SimpleNamespace(ZERO_KEYS=zero, COUNT_QUERIES={key: '' for key in owned}, _query=Mock(return_value=counts), audit=Mock())
        rows = FIXTURE.snapshots()
        proof = {'snapshots': [{key: value for key, value in row.items() if key != 'created_at'} for row in rows],
                 'bindings': [{'id': 17001 + index, 'finding_id': 9101, 'snapshot_id': row['id'], 'role': 'supporting', 'note': 'F5 original bytes', 'position': index} for index, row in enumerate(rows)]}
        return control, counts, proof

    def test_audit_requires_no_agent_activity_exact_metadata_and_all_body_hashes(self):
        control, counts, proof = self._audit_control()
        with patch.dict('sys.modules', {'findings_fixture_control': control}), patch.object(FIXTURE, 'guest_environment', return_value={}), patch.object(FIXTURE, 'run_sql', return_value=proof), patch.object(FIXTURE, 'audit_bodies', return_value=FIXTURE.body_manifest()) as files:
            result = FIXTURE.audit()
            self.assertTrue(result['evidence_fixture']); self.assertEqual(result['binding_ids'], [17001, 17002])
            self.assertEqual(result['counts'], counts); files.assert_called_once()
        for key, value in [('profiles', 1), ('activity', 1), ('foreign_tasks', 1), ('unsafe_tasks', 1), ('findings', 32), ('traffic_bindings', 3), ('events', 4), ('tasks', True)]:
            control, counts, proof = self._audit_control(); counts[key] = value
            with self.subTest(key=key), patch.dict('sys.modules', {'findings_fixture_control': control}), patch.object(FIXTURE, 'guest_environment', return_value={}), patch.object(FIXTURE, 'run_sql') as sql, patch.object(FIXTURE, 'audit_bodies') as files:
                with self.assertRaises(RuntimeError): FIXTURE.audit()
                sql.assert_not_called(); files.assert_not_called()
        control, counts, proof = self._audit_control(); proof['bindings'][0]['snapshot_id'] = 'wrong'
        with patch.dict('sys.modules', {'findings_fixture_control': control}), patch.object(FIXTURE, 'guest_environment', return_value={}), patch.object(FIXTURE, 'run_sql', return_value=proof), patch.object(FIXTURE, 'audit_bodies') as files:
            with self.assertRaises(RuntimeError): FIXTURE.audit()
            files.assert_not_called()

    def test_prepare_requires_fresh_seed_and_preserves_unknown_sql_outcome(self):
        control, _, _ = self._audit_control(); seed = types.SimpleNamespace(main=Mock())
        with patch.dict('sys.modules', {'findings_fixture_control': control, 'findings_seed_guest': seed}), patch.object(FIXTURE, 'guest_environment', return_value={}), patch.object(FIXTURE, 'write_bodies') as files, patch.object(FIXTURE, 'run_sql') as sql, patch.object(FIXTURE, 'audit', return_value={'proof': True}) as final:
            self.assertEqual(FIXTURE.prepare(), {'proof': True})
            self.assertEqual(control.audit.call_args_list, [unittest.mock.call(fresh=True), unittest.mock.call(fresh=False)])
            seed.main.assert_called_once(); files.assert_called_once(); sql.assert_called_once(); final.assert_called_once()
        control.audit.reset_mock(); seed.main.reset_mock(); control.audit.side_effect = RuntimeError('not fresh')
        with patch.dict('sys.modules', {'findings_fixture_control': control, 'findings_seed_guest': seed}), patch.object(FIXTURE, 'guest_environment', return_value={}), patch.object(FIXTURE, 'write_bodies') as files:
            with self.assertRaises(RuntimeError): FIXTURE.prepare()
            seed.main.assert_not_called(); files.assert_not_called()
        control.audit.side_effect = None
        with patch.dict('sys.modules', {'findings_fixture_control': control, 'findings_seed_guest': seed}), patch.object(FIXTURE, 'guest_environment', return_value={}), patch.object(FIXTURE, 'write_bodies'), patch.object(FIXTURE, 'run_sql', side_effect=RuntimeError('unknown transaction')), patch.object(FIXTURE, 'audit') as final:
            with self.assertRaises(RuntimeError): FIXTURE.prepare()
            final.assert_not_called()

    def test_database_json_type_and_successful_fixed_query_are_checked(self):
        for output in (b'[]', b'true', b'null', b'1'):
            response = types.SimpleNamespace(returncode=0, stdout=output)
            with patch.object(FIXTURE.subprocess, 'run', return_value=response), self.assertRaises(RuntimeError):
                FIXTURE.run_sql({}, 'fixed', proof=True)
        response = types.SimpleNamespace(returncode=0, stdout=b'{"fixed":true}')
        with patch.object(FIXTURE.subprocess, 'run', return_value=response) as run:
            self.assertEqual(FIXTURE.run_sql({'PGHOST': '127.0.0.1'}, 'fixed', proof=True), {'fixed': True})
            self.assertEqual(run.call_args.kwargs['input'], b'fixed')
            self.assertEqual(run.call_args.kwargs['timeout'], 20)
