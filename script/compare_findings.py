"""Compare completed native VM and independent pinned-backend evidence; never accepts rendered UI parity."""
import json
from pathlib import Path
import re
import sys

import findings_reference as ref
import findings_fixture_control as control


def require(value, stage):
    if not value: raise RuntimeError('Findings comparison ' + stage)


def number(value, expected):
    require(type(value) is int and value == expected, 'numeric receipt')


def audit(value, *, fresh=False, final=False):
    require(value.get('fixture_audit') is True and value.get('uid') == 1000 and value.get('fresh') is fresh, 'audit identity')
    counts = value['counts']; keys = set(control.ZERO_KEYS) | {'tasks', 'explorations', 'relations', 'companies', 'assets', 'findings', 'finding_nodes', 'events'}
    require(set(counts) == keys and all(type(v) is int and v >= 0 for v in counts.values()), 'audit shape')
    require(all(counts[k] == 0 for k in control.ZERO_KEYS), 'audit activity')
    expected = [0]*5 if fresh else [11,11,1,1,3]
    require([counts[k] for k in ['tasks','explorations','relations','companies','assets']] == expected, 'audit ownership')
    pair = [0,0] if fresh else ([31,31] if final else [33,32])
    require([counts['findings'],counts['finding_nodes']] == pair, 'audit dataset')
    require(counts['events'] == 0 if fresh or not final else counts['events'] <= 3, 'audit events')


def compare(native, inputs, reference):
    require(native.get('stage') == 'complete' and native.get('passed') is True, 'native complete')
    for key in ['seedConfirmed','terminalSuccess','machineStopped']: require(native.get(key) is True, 'native terminal')
    number(native.get('bootAttempts'),3)
    # GuestArtifacts intentionally omits policy fields; observed stopped-boot isolation receipts are authoritative.
    artifacts = inputs['artifacts']
    cpu = artifacts.get('cpuCount',2); require(type(cpu) is int and cpu > 0, 'CPU configuration'); number(native['expectedCPUCount'],cpu)
    boots = native['boots']; require(len(boots) == 3, 'boot count')
    for index, boot in enumerate(boots,1):
        number(boot.get('index'),index); number(boot.get('cpuCount'),cpu); number(boot.get('protectedStatus'),401)
        for key in ['cooperativeStop','machineStopped','passed','reachedReady','credentialLogCheckPassed','isolationVerified','logAuditComplete']:
            require(boot.get(key) is True, 'boot audit')
        require(boot.get('formatStageObserved') is (index == 1) and boot.get('diagnostics') == [], 'boot format/diagnostics')
        require(boot.get('authentication') == ('freshSetup' if index == 1 else 'persistedSession'), 'persisted authentication')
    for key in ['fresh_setup','persisted_session','credentials_absent']: require(reference.get(key) is True, 'reference lifecycle')
    number(reference.get('backend_starts'),3); number(reference.get('cooperative_stops'),3)
    require(reference.get('protected_statuses') == [401,401,401], 'reference protected API')
    network = reference['network_proof']
    require(type(network.get('network_interfaces')) is str and 'lo' in network['network_interfaces'].split(','), 'reference loopback evidence')
    for key in ['network_hardware_devices','network_nonloopback_up','network_external_routes']: number(network.get(key),0)
    require(re.fullmatch('[0-9a-f]{64}',reference.get('networkCheckerSHA256','')) is not None, 'network checker provenance')
    harness = reference['harness']
    for key in ['complete','originalContainersPreserved','inputImagesPreserved','containerRemoved','imageTagRemoved','inputTagsRemoved','exportsComplete']:
        require(harness.get(key) is True, 'reference export/cleanup')
    host = reference['hostIsolation']
    require(host.get('networkMode') == 'none' and host.get('user') == '1000:1000', 'reference isolation identity')
    for key in ['readOnlyRootfs','capDropAll','noNewPrivileges']: require(host.get(key) is True, 'reference isolation guard')
    require(host.get('privileged') is False, 'reference privileges'); number(host.get('hostMounts'),0); number(host.get('ports'),0)
    require(inputs['provenance']['sourceCommit'] == reference.get('sourceCommit') == ref.SOURCE_COMMIT, 'source commit')
    expected_hashes = dict(backendSHA256=inputs['provenance']['backendSHA256'],seedSHA256=inputs['seedSHA256'],controlSHA256=inputs['controlSHA256'])
    for key, wanted in expected_hashes.items():
        require(type(wanted) is str and re.fullmatch('[0-9a-f]{64}',wanted) is not None and reference.get(key) == wanted, 'source/binary hash')
    exercise = native['exercise']; require(exercise.get('passed') is True, 'native exercise')
    checkpoint = exercise['checkpoint']; number(checkpoint.get('schemaVersion'),2); number(checkpoint.get('beforeRequestCount'),123)
    boundary = checkpoint['boundary']
    require(boundary.get('sharedChecks') == ref.BOUNDARY_SHARED and boundary.get('localChecks') == ref.BOUNDARY_LOCAL, 'native boundary coverage')
    number(boundary.get('requestCount'),7); number(boundary.get('diagnosticFieldBytes'),8192)
    require(checkpoint.get('terminalChecks') == ['post_mutation_stats','post_mutation_asset_tree'], 'native aggregate receipt')
    mutation = checkpoint['mutation']; number(mutation.get('requestCount'),14); number(mutation.get('partialHTTPStatus'),500)
    require(mutation.get('checks') == ref.NATIVE_MUTATIONS, 'native state coverage')
    require(checkpoint.get('initialChecks') == ref.read_check_names(False) and exercise.get('finalChecks') == ref.read_check_names(True), 'native read coverage')
    number(exercise.get('afterRequestCount'),100)
    expected = dict(initialChecks=checkpoint['initialChecks'], finalChecks=exercise['finalChecks'],
                    beforeRequestCount=123, afterRequestCount=100, partialHTTPStatus=500, passed=True,
                    boundaryChecks=boundary['sharedChecks'], boundaryRequestCount=7, diagnosticFieldBytes=8192,
                    mutationChecks=[name for name in mutation['checks'] if name in ref.SHARED_MUTATIONS])
    actual = reference['comparison']
    for key, count in [('beforeRequestCount',123),('afterRequestCount',100),('partialHTTPStatus',500),('boundaryRequestCount',7),('diagnosticFieldBytes',8192)]: number(actual.get(key),count)
    require(actual.get('passed') is True and actual == expected, 'common API projection')
    proofs = reference['audit_proofs']; require(set(proofs) == {'seed','before','after'}, 'audit phases')
    require([len(proofs[k]) for k in ['seed','before','after']] == [2,4,2], 'audit receipt count')
    audit(proofs['seed'][0],fresh=True); audit(proofs['seed'][1])
    for i, proof in enumerate(proofs['before']): audit(proof,final=i == 3)
    for proof in proofs['after']: audit(proof,final=True)
    return dict(passed=True, scope='shared fixed Findings backend API and same-data persistence', visible_ui_accepted=False,
                sourceCommit=ref.SOURCE_COMMIT, **expected_hashes, initial_read_checks=100, persisted_read_checks=100,
                shared_mutation_checks=ref.SHARED_MUTATIONS, shared_boundary_checks=ref.BOUNDARY_SHARED,
                native_local_validation_checks=ref.BOUNDARY_LOCAL, diagnostic_field_bytes=8192, partial_http_status=500,
                native_only_checks=[name for name in ref.NATIVE_MUTATIONS if name not in ref.SHARED_MUTATIONS],
                native_boots=3, reference_backend_starts=3)


def load(path):
    with Path(path).open('rb') as stream: data = stream.read(4 * 1024 * 1024 + 1)
    require(len(data) <= 4 * 1024 * 1024, 'artifact bound')
    return json.loads(data)


def main():
    require(len(sys.argv) == 4, 'usage: compare_findings.py VM_REPORT VM_INPUTS REFERENCE_REPORT')
    print(json.dumps(compare(*(load(path) for path in sys.argv[1:])),indent=2))


if __name__ == '__main__': main()
