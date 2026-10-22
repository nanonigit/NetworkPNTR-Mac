"""Do not allow a kernel experiment to overwrite or mix backend artifacts."""
from pathlib import Path
import hashlib
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
import assemble_source_profile
from prepare_kernel import REQUIRED_CONFIG


def put(root, name, data):
    (root / name).write_bytes(data)
    return hashlib.sha256(data).hexdigest()


class SourceProfileTests(unittest.TestCase):
    def fixture(self, root):
        backend = root / 'backend'; backend.mkdir()
        kernel = root / 'kernel'; kernel.mkdir()
        system = put(backend, 'system.ext4', b'fixture readonly system')
        initrd = put(backend, 'initramfs.cpio.gz', b'fixture unused initrd')
        image = bytearray(64); image[56:60] = b'ARM\x64'
        digest = put(kernel, 'Image', image)
        put(backend, 'Image', image)
        config_text = ''.join(f'{key}={value}\n' if value != 'n' else f'# {key} is not set\n' for key, value in REQUIRED_CONFIG.items())
        config = put(kernel, 'kernel.config', config_text.encode())
        source = assemble_source_profile.SOURCE_COMMIT
        manifest = {'architecture': 'arm64', 'sourceCommit': source, 'systemDisk': 'system.ext4', 'systemDiskSHA256': system,
                    'networkDevices': 0, 'hostShares': 0, 'kernel': 'Image', 'kernelSHA256': digest,
                    'initramfs': 'initramfs.cpio.gz', 'initramfsSHA256': initrd}
        (backend / 'manifest.json').write_text(json.dumps(manifest))
        self.lock = assemble_source_profile.load_lock()
        files = {'Image': digest, 'kernel.config': config}
        for name in ['linux-source.tar.xz', 'config-LICENSE', 'COPYING', 'LICENSES.tar.gz']:
            files[name] = put(kernel, name, ('fixture ' + name).encode())
        self.lock['source']['sha256'] = files['linux-source.tar.xz']
        self.lock['config_license']['sha256'] = files['config-LICENSE']
        report = {'kernelSHA256': digest, 'configSHA256': config, 'packageLockSHA256': self.lock['builder_packages_sha256']}
        files['build-report.json'] = put(kernel, 'build-report.json', json.dumps(report).encode())
        build = {'version': '6.12.114', 'source': self.lock['source'], 'configSource': self.lock['config'],
                 'networkMode': 'none', 'hostShares': 0, 'recipeSHA256': 'a' * 64, 'files': files}
        (kernel / 'kernel-build.json').write_text(json.dumps(build))
        return backend, kernel

    def assemble(self, backend, kernel, output):
        with patch('assemble_source_profile.load_lock', return_value=self.lock):
            assemble_source_profile.assemble(backend, kernel, output)

    def test_profile_preserves_system_bytes_and_selects_direct_root_one_cpu(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); backend, kernel = self.fixture(root)
            output = root / 'candidate'
            self.assemble(backend, kernel, output)
            result = json.loads((output / 'manifest.json').read_text())
            self.assertEqual(result['bootMode'], 'rootDisk'); self.assertEqual(result['cpuCount'], 1)
            self.assertEqual(result['sourceCommit'], assemble_source_profile.SOURCE_COMMIT)
            self.assertEqual((output / 'system.ext4').read_bytes(), (backend / 'system.ext4').read_bytes())
            with self.assertRaises(ValueError):
                self.assemble(backend, kernel, output)

    def test_corruption_wrong_source_and_symlinks_do_not_create_candidate(self):
        for invalid in ['corrupt', 'traversal', 'source', 'link']:
            with self.subTest(invalid=invalid), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); backend, kernel = self.fixture(root)
                manifest = json.loads((backend / 'manifest.json').read_text())
                if invalid == 'corrupt':
                    (backend / 'system.ext4').write_bytes(b'changed')
                elif invalid == 'traversal':
                    manifest['systemDisk'] = '../outside'
                elif invalid == 'source':
                    manifest['sourceCommit'] = 'other'
                else:
                    (kernel / 'Image').unlink(); (kernel / 'Image').symlink_to(backend / 'Image')
                (backend / 'manifest.json').write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    self.assemble(backend, kernel, root / 'candidate')
                self.assertFalse((root / 'candidate').exists())

    def test_missing_provenance_and_rehashed_source_substitution_are_rejected(self):
        for missing in sorted(assemble_source_profile.ALLOWED_KERNEL_FILES):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); backend, kernel = self.fixture(root)
                build = json.loads((kernel / 'kernel-build.json').read_text())
                del build['files'][missing]; (kernel / missing).unlink()
                (kernel / 'kernel-build.json').write_text(json.dumps(build))
                with self.assertRaises(ValueError):
                    self.assemble(backend, kernel, root / 'candidate')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); backend, kernel = self.fixture(root)
            build = json.loads((kernel / 'kernel-build.json').read_text())
            build['files']['linux-source.tar.xz'] = put(kernel, 'linux-source.tar.xz', b'substituted source')
            (kernel / 'kernel-build.json').write_text(json.dumps(build))
            with self.assertRaises(ValueError):
                self.assemble(backend, kernel, root / 'candidate')
