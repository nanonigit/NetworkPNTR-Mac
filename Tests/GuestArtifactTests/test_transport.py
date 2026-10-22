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

    def test_large_bidirectional_stream_preserves_bytes_and_half_close(self):
        import threading
        client, guest_input = socket.socketpair()
        guest_output, backend = socket.socketpair()
        payload = b'fixture-request-' * 40000
        reply = b'fixture-response-' * 40000
        errors = []

        def relay():
            try:
                vsock_relay.forward(guest_input, guest_output)
            except Exception as error:
                errors.append(error)
            finally:
                guest_input.close()
                guest_output.close()

        def service():
            try:
                received = bytearray()
                while data := backend.recv(16384):
                    received.extend(data)
                self.assertEqual(received, payload)
                backend.sendall(reply)
                backend.shutdown(socket.SHUT_WR)
            except Exception as error:
                errors.append(error)
            finally:
                backend.close()

        for connection in [client, backend]:
            connection.settimeout(5)
        workers = [threading.Thread(target=relay, daemon=True), threading.Thread(target=service, daemon=True)]
        for worker in workers:
            worker.start()
        try:
            client.sendall(payload)
            client.shutdown(socket.SHUT_WR)
            response = bytearray()
            while data := client.recv(16384):
                response.extend(data)
            self.assertEqual(response, reply)
        finally:
            client.close()
            for worker in workers:
                worker.join(5)
        self.assertFalse(errors)
        self.assertTrue(all(not worker.is_alive() for worker in workers))
