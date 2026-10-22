"""Source-built kernel inputs and offline-profile boundaries."""
from pathlib import Path
import hashlib
import json
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
import prepare_kernel


class KernelSourceTests(unittest.TestCase):
    def test_lock_pins_source_config_and_builder(self):
        lock = prepare_kernel.load_lock()
        self.assertEqual(lock['version'], '6.12.114')
        self.assertEqual(len(lock['source']['sha256']), 64)
        self.assertIn('@sha256:', lock['builder_image'])
        self.assertNotIn('/Applications/', json.dumps(lock))

    def test_cached_inputs_reject_mismatch_symlink_and_oversize(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'input'
            path.write_bytes(b'fixture')
            digest = hashlib.sha256(b'fixture').hexdigest()
            self.assertEqual(prepare_kernel.verified_file(path, digest, 32), path)
            with self.assertRaises(ValueError):
                prepare_kernel.verified_file(path, '0' * 64, 32)
            with self.assertRaises(ValueError):
                prepare_kernel.verified_file(path, digest, 2)
            link = Path(directory) / 'link'
            link.symlink_to(path)
            with self.assertRaises(ValueError):
                prepare_kernel.verified_file(link, digest, 32)

    def test_resolved_configuration_requires_builtin_transport_and_hardening(self):
        values = dict(prepare_kernel.REQUIRED_CONFIG)
        prepare_kernel.validate_config(values)
        for key in ['CONFIG_VIRTIO_VSOCKETS', 'CONFIG_EXT4_FS', 'CONFIG_HARDENED_USERCOPY']:
            with self.subTest(key=key):
                invalid = dict(values); invalid[key] = 'm'
                with self.assertRaises(ValueError):
                    prepare_kernel.validate_config(invalid)
        values['CONFIG_MODULES'] = 'y'
        with self.assertRaises(ValueError):
            prepare_kernel.validate_config(values)

    def test_remote_or_ambiguous_builders_are_rejected(self):
        prepare_kernel.validate_builder_inspection('Driver: docker\nEndpoint: desktop-linux\n', 'desktop-linux')
        for text in ['Driver: remote\nEndpoint: cloud\n', 'Driver: docker\nEndpoint: other\n',
                     'Driver: docker\nEndpoint: desktop-linux\nEndpoint: cloud\n']:
            with self.assertRaises(ValueError):
                prepare_kernel.validate_builder_inspection(text, 'desktop-linux')

    def test_retained_source_uses_verified_staging_and_rejects_substitution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); context = root / 'context'; context.mkdir(); target = root / 'target'; target.mkdir()
            lock = {}
            for key, name in [('source', 'linux-source.tar.xz'), ('config_license', 'config-LICENSE')]:
                data = ('fixture ' + key).encode(); (context / name).write_bytes(data)
                lock[key] = {'sha256': hashlib.sha256(data).hexdigest(), 'maximum_bytes': 100}
            (root / 'changed-download-cache').write_bytes(b'new unverified download')
            prepare_kernel.retain_pinned_inputs(context, target, lock)
            self.assertEqual((target / 'linux-source.tar.xz').read_bytes(), b'fixture source')
            (context / 'linux-source.tar.xz').write_bytes(b'substitution')
            with self.assertRaises(ValueError):
                prepare_kernel.retain_pinned_inputs(context, target, lock)

    def test_arm64_image_and_output_must_be_real_regular_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / 'Image'; data = bytearray(64); data[56:60] = b'ARM\x64'; image.write_bytes(data)
            prepare_kernel.validate_image(image)
            image.write_bytes(b'wrong')
            with self.assertRaises(ValueError):
                prepare_kernel.validate_image(image)
            with self.assertRaises(ValueError):
                prepare_kernel.require_new_output(root)
            link = root / 'link'; link.symlink_to(root / 'new')
            with self.assertRaises(ValueError):
                prepare_kernel.require_new_output(link)
