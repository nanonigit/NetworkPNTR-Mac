import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
from local_session_packaging import verify


class LocalSessionPackagingTests(unittest.TestCase):
    def test_rejects_input_inside_replaced_bundle_including_case_alias(self):
        root = Path(tempfile.gettempdir()) / 'NetworkPNTR-Packaging-Fixture.app'
        for bundle in [root, Path(str(root).lower())]:
            with self.assertRaises(ValueError):
                verify(root / 'Contents/Resources/Guest', bundle)

    def test_validates_native_capability_and_all_input_bytes_before_replacement(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); guest = root / 'guest'; guest.mkdir()
            manifest = {'sourceCommit':'e75ae371ad777ffd1eecdd28d2781a6519b05591','managedCapabilities':['native-local-session-v1']}
            for key,name in {'kernel':'Image','initramfs':'initramfs.cpio.gz','systemDisk':'system.ext4'}.items():
                (guest / name).write_bytes(key.encode())
                manifest[key] = name
                manifest[key+'SHA256'] = hashlib.sha256(key.encode()).hexdigest()
            path = guest/'manifest.json'; path.write_text(json.dumps(manifest))
            verify(guest, root/'Output.app')
            (guest/'Image').write_bytes(b'tampered')
            with self.assertRaises(ValueError):verify(guest, root/'Output.app')
            (guest/'Image').write_bytes(b'kernel')
            manifest['kernel'] = 'kernel'
            path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):verify(guest, root/'Output.app')
            manifest['kernel'] = 'Image'
            manifest['managedCapabilities'] = 'native-local-session-v1'
            path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):verify(guest, root/'Output.app')
            manifest['managedCapabilities'] = []
            path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):verify(guest, root/'Output.app')


if __name__ == '__main__':unittest.main()
