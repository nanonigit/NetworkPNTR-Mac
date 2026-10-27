"""Independent reference checks: fixed goldens and mutated replies, never backend acceptance from mocks."""
import importlib.util
import json
from pathlib import Path
import sys
import unicodedata
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'script'))
SPEC = importlib.util.spec_from_file_location('findings_reference', ROOT / 'script/findings_reference.py')
reference = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reference)


class Wire:
    def __init__(self):
        self.calls = []
        self.reply = (200, {})
        self.on_reply = lambda: None

    def request(self, method, path, body=None):
        self.calls.append((method, path, body)); self.on_reply()
        return self.reply


class FindingsReferenceTests(unittest.TestCase):
    def goldens(self):
        return json.loads((ROOT / 'Tests/ArtexCoreTests/Fixtures/findings-runtime-aggregates.json').read_text())

    def wire_row(self, expected):
        row = dict(expected, id=str(expected['id']), finding_id=str(expected['id']))
        row['task_id'] = str(expected['task_id']) if expected['task_id'] else None
        row['task_description'] = f"F4 terminal task {expected['task_id']} {reference.seed.LITERAL}" if expected['task_id'] else ''
        labels = {8201: ('root_domain', 'fixture.example.test'), 8202: ('subdomain', 'api.fixture.example.test'), 8203: ('ip', '198.51.100.9')}
        row['assets'] = [dict(id=str(a), type=labels[a][0], label=labels[a][1]) for a in expected['asset_ids']]
        return row

    def test_filter_vectors_and_initial_durable_aggregate_goldens(self):
        for persisted in [False, True]:
            rows = reference.dataset(persisted)
            data = self.goldens()['persisted' if persisted else 'initial']
            reference.verify_stats(data['stats'], rows)
            reference.verify_tree(data['tree'], rows)
            for sort in ['severity', 'time']:
                groups = data['groups'] if sort == 'severity' else sorted(data['groups'], key=lambda g: g['last_found_at'], reverse=True)
                for page in [1, 2, 3]:
                    query = dict(page=page, limit=10, sort=sort)
                    actual = dict(items=groups[(page-1)*10:page*10], total=12, finding_total=len(rows), page=page, page_size=10)
                    reference.verify_groups(actual, query, rows)
        rows = reference.dataset(False); vectors = reference.vectors()
        self.assertEqual(len(vectors), 43)
        self.assertEqual([r['id'] for r in reference.match(rows, dict(sort='severity'))][:9], [9133, 9129, 9125, 9121, 9117, 9113, 9109, 9105, 9101])
        self.assertEqual([r['id'] for r in reference.match(rows, vectors[-1][1])], [9102])
        self.assertEqual(reference.match(rows, dict(q='F4 é')), [])
        self.assertEqual(len(reference.match(rows, dict(asset_scope='__none__'))), 7)
        self.assertEqual(len(reference.read_check_names(False)), 100); self.assertEqual(len(reference.read_check_names(True)), 100)

    def test_raw_row_fields_asset_order_and_unicode_normalization_are_checked(self):
        for expected in reference.dataset(False):
            reference.verify_row(self.wire_row(expected), expected)
        expected = reference.dataset(False)[1]; original = self.wire_row(expected)
        for field in ['id', 'finding_id', 'task_id', 'task_description', 'name', 'vulnclass', 'severity', 'status', 'summary', 'evidence', 'report', 'ts']:
            changed = dict(original); changed[field] = 'changed'
            with self.assertRaises(RuntimeError):
                reference.verify_row(changed, expected)
        for field in ['name', 'summary', 'evidence', 'report']:
            changed = dict(original); changed[field] = unicodedata.normalize('NFC', original[field])
            with self.assertRaises(RuntimeError):
                reference.verify_row(changed, expected)
        changed = dict(original); changed['assets'] = list(reversed(changed['assets']))
        with self.assertRaises(RuntimeError): reference.verify_row(changed, expected)
        for field in ['traffic_count', 'evidence_version', 'report_evidence_version', 'report_stale', 'intent_id', 'param_id', 'source_task_id', 'inherited']:
            changed = dict(original); changed[field] = '9999' if field.endswith('_id') else True
            with self.assertRaises(RuntimeError): reference.verify_row(changed, expected)

    def test_aggregate_metadata_counts_and_order_drift_cannot_pass(self):
        rows = reference.dataset(False); initial = self.goldens()['initial']
        for key in ['total', 'pending', 'critical', 'high', 'medium', 'low']:
            value = dict(initial['stats']); value[key] += 1
            with self.assertRaises(RuntimeError): reference.verify_stats(value, rows)
        value = json.loads(json.dumps(initial['stats'])); value['tasks'][0]['description'] = 'changed'
        with self.assertRaises(RuntimeError): reference.verify_stats(value, rows)
        value = json.loads(json.dumps(initial['tree'])); value['nodes'][1]['self'] += 1
        with self.assertRaises(RuntimeError): reference.verify_tree(value, rows)
        for key in ['parent', 'kind', 'label', 'last_found_at', 'company_id']:
            value = json.loads(json.dumps(initial['tree'])); value['nodes'][1][key] = 'changed'
            with self.assertRaises(RuntimeError): reference.verify_tree(value, rows)
        value = json.loads(json.dumps(initial['tree'])); value['nodes'].reverse()
        with self.assertRaises(RuntimeError): reference.verify_tree(value, rows)
        value = dict(items=initial['groups'][:10], total=12, finding_total=33, page=1, page_size=10)
        changed = json.loads(json.dumps(value)); changed['items'][1]['task_status'] = 'running'
        with self.assertRaises(RuntimeError): reference.verify_groups(changed, dict(page=1, limit=10, sort='severity'), rows)

    def test_finite_client_rejects_unsafe_routes_queries_and_bodies_before_dispatch(self):
        wire = Wire(); client = reference.Bounded(wire)
        for method, path, body in [('GET', 'https://outside.invalid/api/exploration/findings', None),
                                   ('POST', '/api/tasks', {}), ('GET', '/api/exploration/findings/9101/retest', None),
                                   ('GET', '/api/exploration/findings/9%31%30%31', None),
                                   ('GET', '/api/exploration/findings?page=1&page=2&limit=20', None),
                                   ('GET', '/api/exploration/findings?page=9&limit=20', None),
                                   ('GET', '/api/exploration/findings?task=9999', None),
                                   ('PATCH', '/api/exploration/findings/9101', {'status': 'foreign'}),
                                   ('PATCH', '/api/exploration/findings/9101', {'name': 'a' * 8193}),
                                   ('PATCH', '/api/exploration/findings/9101', {'name': '\0' * 6000, 'vulnclass': '\0' * 6000}),
                                   ('DELETE', '/api/exploration/findings/9103', None)]:
            with self.assertRaises(RuntimeError): client.request(method, path, body)
        self.assertEqual(wire.calls, [])
        wire.reply = (500, {'error': 'fixture'})
        self.assertEqual(client.request('PATCH', '/api/exploration/findings/9101', dict(name=reference.NUL_NAME, status='risk_accepted'))[0], 500)
        self.assertEqual(len(wire.calls), 1)

    def test_client_count_and_deadline_before_and_after_dispatch(self):
        clock = [0.0]; wire = Wire(); client = reference.Bounded(wire, clock=lambda: clock[0], maximum=1)
        client.request('GET', '/api/exploration/findings/stats')
        with self.assertRaises(RuntimeError): client.request('GET', '/api/exploration/findings/stats')
        self.assertEqual(len(wire.calls), 1)
        wire = Wire(); clock[0] = 0; late = reference.Bounded(wire, clock=lambda: clock[0])
        wire.on_reply = lambda: clock.__setitem__(0, 91.0)
        with self.assertRaises(RuntimeError): late.request('GET', '/api/exploration/findings/stats')
        self.assertEqual(len(wire.calls), 1)
        for maximum in [0, 129, True, -1]:
            with self.assertRaises(RuntimeError): reference.Bounded(Wire(), maximum=maximum)

    def test_inactive_virtual_tunnels_are_allowed_but_active_hardware_or_routes_are_rejected(self):
        from unittest.mock import patch
        proof = dict(network_interfaces='gre0,lo,tunl0', network_hardware_devices=0, network_nonloopback_up=0, network_external_routes=0)
        with patch.object(reference.check_network, 'inspect', return_value=proof):
            self.assertEqual(reference.inspect_network(), proof)
        for key in ['network_hardware_devices','network_nonloopback_up','network_external_routes']:
            changed = dict(proof); changed[key] = 1
            with patch.object(reference.check_network, 'inspect', return_value=changed), self.assertRaises(RuntimeError):
                reference.inspect_network()

    def test_individual_remote_boundaries_preserve_all_fields_and_restore_original(self):
        import copy
        testcase = self
        go_space = ''.join(chr(n) for n in list(range(9,14))+[32,0x85,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000]+list(range(0x2000,0x200B)))
        class Backend:
            def __init__(self, corrupt=None):
                self.row = testcase.wire_row(reference.dataset(False)[0]); self.fields = []; self.calls = 0; self.corrupt = corrupt
            def request(self, method, path, body=None):
                testcase.assertEqual(path, reference.BASE+'/9101'); self.calls += 1
                if method == 'PATCH':
                    self.fields.append(set(body))
                    for key, value in body.items(): self.row[key] = value.strip(go_space) if key in ('name','vulnclass') else value
                else: testcase.assertEqual(method, 'GET')
                if self.calls == self.corrupt: self.row['summary'] = 'unexpected unrelated write'
                return 200, copy.deepcopy(self.row)
        backend = Backend(); client = reference.Bounded(backend)
        proof = reference.boundaries(client)
        self.assertEqual(client.calls, 7); self.assertEqual(proof, dict(boundaryChecks=reference.BOUNDARY_SHARED, boundaryRequestCount=7, diagnosticFieldBytes=8192))
        self.assertEqual(backend.fields,[{'name'},{'vulnclass'},{'severity'},{'name'},{'vulnclass'},{'name','vulnclass','severity'}])
        reference.verify_row(backend.row, reference.dataset(False)[0])
        for index in range(1,8):
            backend = Backend(corrupt=index); client = reference.Bounded(backend)
            with self.assertRaises(RuntimeError): reference.boundaries(client)
            self.assertEqual(client.calls,index)

    def test_host_main_refused_before_process_or_network(self):
        from unittest.mock import patch
        with patch.object(reference.platform, 'system', return_value='Darwin'), patch.object(reference.subprocess, 'Popen') as process:
            with self.assertRaises(RuntimeError): reference.main()
            process.assert_not_called()


if __name__ == '__main__':
    unittest.main()
