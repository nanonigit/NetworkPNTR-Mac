from io import BytesIO
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import stat
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'guest'))
import check_blank_disk


class BlankDiskTests(unittest.TestCase):
    def test_short_reads_reuse_the_buffer_and_detect_later_data(self):
        class ShortReadStream(BytesIO):
            def readinto(self, buffer):
                self.buffers.append(buffer)
                return super().readinto(memoryview(buffer)[:3])

        stream = ShortReadStream(b'\0' * 7 + b'x')
        stream.buffers = []
        with patch.object(Path, 'open', return_value=stream):
            self.assertFalse(check_blank_disk.is_blank(Path('/fixture')))
        self.assertEqual(len(stream.buffers), 3)
        self.assertTrue(all(buffer is stream.buffers[0] for buffer in stream.buffers))

    def test_indeterminate_read_is_an_execution_failure(self):
        with patch.object(Path, 'stat', return_value=SimpleNamespace(st_mode=stat.S_IFBLK)):
            with patch.object(Path, 'open') as open_disk:
                open_disk.return_value.__enter__.return_value.readinto.return_value = None
                self.assertEqual(check_blank_disk.check_status(Path('/fixture')), 3)

    def test_full_disk_is_checked_without_modification(self):
        with tempfile.TemporaryDirectory() as directory:
            disk = Path(directory) / 'disk'
            with disk.open('wb') as file:
                file.truncate(3 * 1024 * 1024)
            self.assertTrue(check_blank_disk.is_blank(disk))
            with disk.open('r+b') as file:
                file.seek(-1, 2)
                file.write(b'x')
            self.assertFalse(check_blank_disk.is_blank(disk))
            self.assertEqual(disk.read_bytes()[-1:], b'x')

    def test_missing_file_is_not_treated_as_blank(self):
        with self.assertRaises(FileNotFoundError):
            check_blank_disk.is_blank(Path('/nonexistent-artex-test/disk'))

    def test_cli_status_distinguishes_nonblank_invalid_device_and_read_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'disk'
            path.write_bytes(b'\0' * 16)
            self.assertEqual(check_blank_disk.check_status(path), 3)
            with patch.object(Path, 'stat', return_value=SimpleNamespace(st_mode=stat.S_IFBLK)):
                self.assertEqual(check_blank_disk.check_status(path), 0)
                path.write_bytes(b'x')
                self.assertEqual(check_blank_disk.check_status(path), 2)
                with patch('check_blank_disk.is_blank', side_effect=OSError('private-secret')):
                    self.assertEqual(check_blank_disk.check_status(path), 3)
        self.assertEqual(check_blank_disk.check_status(Path('/nonexistent-artex-test/disk')), 3)
