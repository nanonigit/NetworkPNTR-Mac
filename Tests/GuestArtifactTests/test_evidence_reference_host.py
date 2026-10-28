"""The host bridge compares fixed exported bytes and must remain inert on import."""
import hashlib
import importlib.util
import os
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
