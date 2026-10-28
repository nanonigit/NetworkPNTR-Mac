"""The host bridge compares fixed exported bytes and must remain inert on import."""
import ast
import hashlib
import importlib.util
import os
import json
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2] / 'script/evidence_reference_host.py'
SPEC = importlib.util.spec_from_file_location('evidence_reference_host', SOURCE)
HOST = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(HOST)

class EvidenceReferenceHostTests(unittest.TestCase):
    def test_independent_full_byte_comparison_handles_empty_binary_and_corruption(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); left, right = root / 'left', root / 'right'
            for data in (b'', bytes(range(256)) * 257 + b'end'):
                left.write_bytes(data); right.write_bytes(data); digest = hashlib.sha256(data).hexdigest()
                proof = HOST.compare_files(left, right, len(data), digest)
                self.assertEqual(proof, {'bytes': len(data), 'sha256': digest, 'byte_equal': True})
                right.write_bytes((b'x' + data[1:]) if data else b'x')
                with self.assertRaises(RuntimeError): HOST.compare_files(left, right, len(data), digest)

    def test_symlinks_special_files_wrong_length_and_hash_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); left, right = root / 'left', root / 'right'
            left.write_bytes(b'original'); right.write_bytes(b'original'); digest = hashlib.sha256(b'original').hexdigest()
            with self.assertRaises(RuntimeError): HOST.compare_files(left, right, 1, digest)
            with self.assertRaises(RuntimeError): HOST.compare_files(left, right, 8, '0' * 64)
            link = root / 'link'; link.symlink_to(left)
            fifo = root / 'fifo'; os.mkfifo(fifo, 0o600)
            for path in (link, fifo, root):
                with self.assertRaises(RuntimeError): HOST.compare_files(path, right, 8, digest)
            self.assertEqual(left.read_bytes(), b'original')

    def test_bootstrap_sql_has_actual_newlines_and_all_embedded_programs_parse(self):
        for name in ('INSTALL', 'SETUP', 'EXECUTE', 'DUMP', 'EXPORT'):
            ast.parse(getattr(HOST, name))
        tree = ast.parse(HOST.SETUP)
        node = next(n for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'sql' for t in n.targets))
        self.assertTrue(all(isinstance(n, (ast.BinOp, ast.Add, ast.Constant, ast.Name, ast.Load)) for n in ast.walk(node.value)))
        sql = eval(compile(ast.Expression(node.value), '<fixed bootstrap SQL>', 'eval'), {'__builtins__': {}, 'password': 'a' * 64})
        self.assertIn('\nCREATE DATABASE artex OWNER artex;\n', sql)
        self.assertNotIn('\\n', sql)

    def test_builder_proof_names_the_exact_local_builder_and_rejects_other_endpoints(self):
        local = 'Name: desktop-linux\nDriver: docker\nNodes:\nName: desktop-linux\nEndpoint: desktop-linux\n'
        self.assertTrue(HOST.builder_is_local(local))
        for bad in (local.replace('Driver: docker', 'Driver: remote'), local.replace('Endpoint: desktop-linux', 'Endpoint: ssh://outside'), local.replace('Name: desktop-linux', 'Name: other'), local + 'Endpoint: extra\n'):
            self.assertFalse(HOST.builder_is_local(bad))

    def test_native_receipt_requires_private_exit_report_binary_and_current_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); workspace, repo = root / 'native', root / 'repo'
            (workspace / 'run').mkdir(parents=True); (repo / 'Sources').mkdir(parents=True)
            binary = workspace / 'VMProbe'; binary.write_bytes(b'known signed probe identity')
            source = repo / 'Sources/fixed.swift'; source.write_bytes(b'fixed native source')
            sources = {'Sources/fixed.swift': hashlib.sha256(source.read_bytes()).hexdigest()}
            private_report = {'nativeProbePassed': True, 'machineStopped': True, 'cleanupComplete': True, 'witnessedInFlightCancellation': True, 'witnessedVMStop': True}
            inputs = {'nativeHead': 'a' * 40, 'probeSHA256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'sourceSHA256': sources}
            record = {'nativeHead': inputs['nativeHead'], 'nativeBinarySHA256': inputs['probeSHA256'], 'observedExitCode': 0, 'report': private_report, 'inputSourceSHA256': sources}
            (workspace / 'inputs.json').write_text(json.dumps(inputs)); (workspace / 'run/evidence-native.json').write_text(json.dumps(private_report)); (workspace / 'exit-code.txt').write_text('0')
            HOST.verify_native_receipt(record, workspace, repo)
            (workspace / 'exit-code.txt').write_text('1')
            with self.assertRaises(RuntimeError): HOST.verify_native_receipt(record, workspace, repo)
            (workspace / 'exit-code.txt').write_text('0')
            changed = dict(private_report, machineStopped=False); (workspace / 'run/evidence-native.json').write_text(json.dumps(changed))
            with self.assertRaises(RuntimeError): HOST.verify_native_receipt(record, workspace, repo)
            (workspace / 'run/evidence-native.json').write_text(json.dumps(private_report))
            source.write_bytes(b'changed source')
            with self.assertRaises(RuntimeError): HOST.verify_native_receipt(record, workspace, repo)
            source.write_bytes(b'fixed native source'); binary.write_bytes(b'replaced executable')
            with self.assertRaises(RuntimeError): HOST.verify_native_receipt(record, workspace, repo)
