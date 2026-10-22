from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'guest'))
import check_blank_disk


class BlankDiskTests(unittest.TestCase):
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
