import gzip
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "script"))
import prepare_guest


class KernelPackagingTests(unittest.TestCase):
    def image(self):
        data = bytearray(80)
        data[56:60] = b"ARM\x64"
        return bytes(data)

    def wrapper(self):
        payload = gzip.compress(self.image(), mtime=0)
        header = bytearray(64)
        header[:2] = b"MZ"
        header[4:8] = b"zimg"
        struct.pack_into("<II", header, 8, 64, len(payload))
        header[24:28] = b"gzip"
        return bytes(header) + payload

    def test_raw_image_is_accepted(self):
        self.assertEqual(prepare_guest.unpack_kernel(self.image()), self.image())

    def test_efi_zboot_extracts_the_raw_image(self):
        self.assertEqual(prepare_guest.unpack_kernel(self.wrapper()), self.image())

    def test_truncated_payload_and_unknown_image_are_rejected(self):
        with self.assertRaises(ValueError):
            prepare_guest.unpack_kernel(self.wrapper()[:-8])
        with self.assertRaises(ValueError):
            prepare_guest.unpack_kernel(b"not a Linux Image")


if __name__ == "__main__":
    unittest.main()
