"""The host bridge compares fixed exported bytes and must remain inert on import."""
import ast
import hashlib
import importlib.util
import os
import sys
import time
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

    def test_stream_export_copies_binary_without_archive_or_host_mount(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'copied.bin'
            data = bytes(range(256)) * 300
            command = [sys.executable, '-c', 'import sys;sys.stdout.buffer.write(bytes(range(256))*300)']
            HOST.copy_response_file(command, output, len(data), timeout=2)
            self.assertEqual(output.read_bytes(), data)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            ast.parse(HOST.EXPORT_ONE)

    def test_stream_export_rejects_short_extra_nonzero_and_excess_stderr(self):
        programs = ["import sys;sys.stdout.buffer.write(b'x')", "import sys;sys.stdout.buffer.write(b'xxx')", "import sys;sys.stdout.buffer.write(b'xx');sys.exit(7)", "import sys;sys.stderr.buffer.write(b'x'*65537)"]
        for code in programs:
            with self.subTest(code=code), tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(RuntimeError):
                    HOST.copy_response_file([sys.executable, '-c', code], Path(directory) / 'invalid.bin', 2, timeout=2)

    def test_stream_export_timeout_is_bounded_and_existing_files_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'timeout.bin'; started = time.monotonic()
            with self.assertRaises(RuntimeError): HOST.copy_response_file([sys.executable, '-c', 'import time;time.sleep(10)'], output, 0, timeout=.1)
            self.assertLess(time.monotonic() - started, 2)
            sentinel = Path(directory) / 'keep.bin'; sentinel.write_bytes(b'keep')
            with self.assertRaises(RuntimeError): HOST.copy_response_file([sys.executable, '-c', 'raise RuntimeError("must not start")'], sentinel, 0, timeout=1)
            self.assertEqual(sentinel.read_bytes(), b'keep')
