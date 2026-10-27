"""Completion requires lifecycle/source-bound artifacts, not a copied passed flag."""
import copy
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]; sys.path.insert(0, str(ROOT / 'script'))
SPEC = importlib.util.spec_from_file_location('compare_findings', ROOT / 'script/compare_findings.py')
compare = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(compare)
import findings_reference as reference
import findings_fixture_control as control


class FindingCompareTests(unittest.TestCase):
    def receipts(self):
        before = dict(schemaVersion=1, beforeRequestCount=116, initialChecks=reference.read_check_names(False),
                      terminalChecks=['post_mutation_stats', 'post_mutation_asset_tree'],
                      mutation=dict(checks=reference.NATIVE_MUTATIONS, partialHTTPStatus=500, requestCount=14))
        exercise = dict(checkpoint=before, finalChecks=reference.read_check_names(True), afterRequestCount=100, passed=True)
        boots = []
        for i in (1, 2, 3):
            boots.append(dict(index=i, cpuCount=1, authentication='freshSetup' if i == 1 else 'persistedSession', protectedStatus=401,
                              cooperativeStop=True, machineStopped=True, passed=True, reachedReady=True, credentialLogCheckPassed=True,
                              isolationVerified=True, logAuditComplete=True, diagnostics=[], formatStageObserved=i == 1))
        native = dict(stage='complete', bootAttempts=3, expectedCPUCount=1, boots=boots, seedConfirmed=True, terminalSuccess=True, machineStopped=True, passed=True, exercise=exercise)
        inputs = dict(provenance=dict(sourceCommit=reference.SOURCE_COMMIT, backendSHA256='a' * 64), seedSHA256='b' * 64, controlSHA256='c' * 64,
                      artifacts=dict(networkDevices=0, hostShares=0, cpuCount=1))
        shared = dict(initialChecks=reference.read_check_names(False), finalChecks=reference.read_check_names(True), beforeRequestCount=116,
                      afterRequestCount=100, mutationChecks=reference.SHARED_MUTATIONS, partialHTTPStatus=500, passed=True)
        def audit(fresh=False, final=False):
            counts = {k: 0 for k in control.ZERO_KEYS}
            counts.update(tasks=0 if fresh else 11, explorations=0 if fresh else 11, relations=0 if fresh else 1, companies=0 if fresh else 1,
                          assets=0 if fresh else 3, findings=0 if fresh else (31 if final else 33), finding_nodes=0 if fresh else (31 if final else 32), events=3 if final else 0)
            return dict(fixture_audit=True, uid=1000, fresh=fresh, counts=counts)
        ref = dict(comparison=shared, backend_starts=3, cooperative_stops=3, fresh_setup=True, persisted_session=True, credentials_absent=True,
                   network_devices=0, protected_statuses=[401]*3, sourceCommit=reference.SOURCE_COMMIT, backendSHA256='a'*64, seedSHA256='b'*64, controlSHA256='c'*64,
                   audit_proofs=dict(seed=[audit(True), audit()], before=[audit(), audit(), audit(final=True)], after=[audit(final=True), audit(final=True)]),
                   hostIsolation=dict(networkMode='none', user='1000:1000', readOnlyRootfs=True, privileged=False, hostMounts=0, capDropAll=True, noNewPrivileges=True, ports=0),
                   harness=dict(complete=True,originalContainersPreserved=True,inputImagesPreserved=True,containerRemoved=True,imageTagRemoved=True,inputTagsRemoved=True,exportsComplete=True))
        return native, inputs, ref

    def test_complete_common_projection_keeps_native_only_checks_explicit(self):
        result = compare.compare(*self.receipts())
        self.assertTrue(result['passed']); self.assertFalse(result['visible_ui_accepted'])
        self.assertEqual(result['shared_mutation_checks'], reference.SHARED_MUTATIONS)
        self.assertIn('explicit_acknowledgment', result['native_only_checks'])

    def test_missing_or_changed_boot_lifecycle_never_passes_even_with_passed_true(self):
        for key in ['cooperativeStop', 'machineStopped', 'credentialLogCheckPassed', 'isolationVerified', 'logAuditComplete', 'passed', 'reachedReady']:
            native, inputs, ref = self.receipts(); native['boots'][1][key] = False
            with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)
        for field, value in [('formatStageObserved', True), ('authentication', 'freshSetup'), ('cpuCount', 2), ('diagnostics', ['fault'])]:
            native, inputs, ref = self.receipts(); native['boots'][1][field] = value
            with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)
        native, inputs, ref = self.receipts(); native['boots'].pop()
        with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)

    def test_hash_bindings_backend_context_scope_and_native_uncertainty_cannot_be_omitted(self):
        for key in ['backendSHA256', 'seedSHA256', 'controlSHA256', 'sourceCommit']:
            native, inputs, ref = self.receipts(); ref[key] = 'changed'
            with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)
        native, inputs, ref = self.receipts(); native['exercise']['checkpoint']['mutation']['checks'] = reference.SHARED_MUTATIONS
        with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)
        for key in ['initialChecks', 'finalChecks', 'mutationChecks', 'beforeRequestCount', 'afterRequestCount', 'partialHTTPStatus']:
            native, inputs, ref = self.receipts(); ref['comparison'][key] = ['changed'] if 'Checks' in key else 999
            with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)
        for key, value in [('networkMode','bridge'), ('readOnlyRootfs',False), ('privileged',True), ('hostMounts',1), ('ports',1), ('noNewPrivileges',False), ('capDropAll',False), ('user','0')]:
            native, inputs, ref = self.receipts(); ref['hostIsolation'][key] = value
            with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)

    def test_actual_native_input_schema_relies_on_observed_boot_isolation(self):
        import json
        native, _, ref = self.receipts()
        inputs = json.loads((ROOT / 'evidence/findings/f4b-native-source-inputs.json').read_text())
        self.assertNotIn('networkDevices', inputs['artifacts']); self.assertNotIn('hostShares', inputs['artifacts'])
        ref['backendSHA256'] = inputs['provenance']['backendSHA256']
        ref['seedSHA256'] = inputs['seedSHA256']; ref['controlSHA256'] = inputs['controlSHA256']
        self.assertTrue(compare.compare(native, inputs, ref)['passed'])

    def test_incomplete_export_or_cleanup_cannot_be_hidden_by_reference_success(self):
        for key in ['complete','originalContainersPreserved','inputImagesPreserved','containerRemoved','imageTagRemoved','inputTagsRemoved','exportsComplete']:
            native, inputs, ref = self.receipts(); ref['harness'][key] = False
            with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)

    def test_audit_shape_owned_counts_and_activity_are_not_replaced_by_passed_flags(self):
        for key in list(control.ZERO_KEYS) + ['tasks', 'explorations', 'relations', 'companies', 'assets', 'findings', 'finding_nodes', 'events']:
            native, inputs, ref = self.receipts(); ref['audit_proofs']['after'][0]['counts'][key] = 99
            with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)
        native, inputs, ref = self.receipts(); ref['audit_proofs']['seed'][0]['fresh'] = False
        with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)
        native, inputs, ref = self.receipts(); ref['audit_proofs']['before'].pop()
        with self.assertRaises(RuntimeError): compare.compare(native, inputs, ref)


if __name__ == '__main__': unittest.main()
