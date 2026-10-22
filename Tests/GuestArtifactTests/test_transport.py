from pathlib import Path
import socket
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'guest'))
import vsock_relay


class TransportTests(unittest.TestCase):
    def test_exact_credential_frame_only(self):
        token = b'a' * 64
        for frame, accepted in [(b'ARTEX_VSOCK_1 ' + token + b'\n', True),
                                (b'ARTEX_VSOCK_1 ' + b'b' * 64 + b'\n', False),
                                (b'ARTEX_VSOCK_1 ' + token + b'\r\n', False),
                                (b'ARTEX_VSOCK_1 ' + token + b'x\n', False)]:
            first, second = socket.socketpair()
            try:
                first.sendall(frame)
                self.assertEqual(vsock_relay.authenticate(second, token), accepted)
            finally:
                first.close()
                second.close()

    def test_short_eof_is_rejected(self):
        first, second = socket.socketpair()
        try:
            first.sendall(b'ARTEX_')
            first.shutdown(socket.SHUT_WR)
            self.assertFalse(vsock_relay.authenticate(second, b'a' * 64))
        finally:
            first.close()
            second.close()

    def test_oversized_frame_is_bounded(self):
        first, second = socket.socketpair()
        try:
            first.sendall(b'x' * 1000)
            self.assertFalse(vsock_relay.authenticate(second, b'a' * 64))
            self.assertGreater(len(second.recv(1000)), 0)
        finally:
            first.close()
            second.close()
