import gzip
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
import prepare_backend


def entries(compressed):
    data = gzip.decompress(compressed)
    result = {}
    offset = 0
    while offset < len(data):
        header = data[offset:offset + 110]
        if header[:6] != b'070701':
            raise ValueError('Invalid cpio')
        fields = [int(header[6 + index * 8:14 + index * 8], 16) for index in range(13)]
        start = offset + 110
        name = data[start:start + fields[11] - 1].decode()
        start = (start + fields[11] + 3) // 4 * 4
        result[name] = data[start:start + fields[6]]
        offset = (start + fields[6] + 3) // 4 * 4
        if name == 'TRAILER!!!':
            return result
    raise ValueError('Missing trailer')


class BackendPackagingTests(unittest.TestCase):
    def test_kernel_autoload_helper_and_modules_are_present(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'linux.apk'
            with tarfile.open(apk, 'w:gz') as archive:
                info = tarfile.TarInfo('lib/modules/fixture/modules.dep')
                data = b'kernel/fixture.ko:\n'
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
            with patch('prepare_guest.member', return_value=b'fixture busybox'):
                packaged = entries(prepare_backend.module_initramfs(apk, None))
            self.assertEqual(packaged['sbin/modprobe'], b'../bin/busybox')
            self.assertEqual(packaged['lib/modules/fixture/modules.dep'], data)
            self.assertIn(b'switch_root', packaged['init'])
