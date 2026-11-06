import concurrent.futures
import hashlib
import os
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
HEAD = b"HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: close\r\n\r\n"


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun") and shutil.which("openssl"), "macOS system TLS fixture")
class CloudEgressTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(temp.cleanup)
        cls.work = Path(temp.name)
        cls.binary = cls.work / "tls-fixture"
        subprocess.run([
            "xcrun", "clang", "-Wall", "-Wextra", "-Werror", "-Wno-deprecated-declarations", "-DARTEX_CLOUD_TLS_FIXTURE",
            "-I", str(ROOT / "Sources/ArtexCloudTLS/include"),
            str(ROOT / "Sources/ArtexCloudTLS/ArtexCloudTLS.c"),
            str(ROOT / "Tests/GuestArtifactTests/fixtures/cloud_tls_client.c"),
            "-framework", "Security", "-framework", "CoreFoundation", "-o", str(cls.binary),
        ], check=True, capture_output=True, timeout=20)
        commands = [
            ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
             "-subj", "/CN=ARTEX TLS fixture root", "-keyout", "ca.key", "-out", "ca.pem"],
            ["req", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=egress.test",
             "-keyout", "server.key", "-out", "server.csr"],
            ["x509", "-req", "-in", "server.csr", "-CA", "ca.pem", "-CAkey", "ca.key",
             "-CAcreateserial", "-days", "1", "-extfile", "server.ext", "-out", "server.pem"],
        ]
        (cls.work / "server.ext").write_text(
            "subjectAltName=DNS:egress.test\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n", encoding="ascii",
        )
        for command in commands:
            subprocess.run(["openssl", *command], cwd=cls.work, check=True, capture_output=True, timeout=10)
        subprocess.run(["openssl", "x509", "-in", "ca.pem", "-outform", "der", "-out", "ca.der"],
                       cwd=cls.work, check=True, capture_output=True, timeout=10)
        cls.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        cls.context.load_cert_chain(cls.work / "server.pem", cls.work / "server.key")

    def client(self, port, host="egress.test", trusted=True, timeout=2000, limit=4096, mode="normal", env=None):
        anchor = str(self.work / "ca.der") if trusted else "-"
        return subprocess.run(
            [str(self.binary), host, str(port), anchor, str(timeout), str(limit), mode],
            env=env, capture_output=True, timeout=5,
        )

    def exchange(self, serve, *, tls=True, tls_context=None, **client_options):
        with socket.socket() as listener, concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(3)

            def accept():
                connection, _ = listener.accept()
                with connection:
                    connection.settimeout(3)
                    if tls:
                        try:
                            stream = (tls_context or self.context).wrap_socket(connection, server_side=True)
                        except ssl.SSLError:
                            return b""
                        with stream:
                            return serve(stream)
                    return serve(connection)

            future = executor.submit(accept)
            result = self.client(listener.getsockname()[1], **client_options)
            return result, future.result(timeout=4)

    @staticmethod
    def request(stream):
        buffer = b""
        while b"\r\n\r\n" not in buffer and len(buffer) < 4096:
            data = stream.recv(4096)
            if not data:
                break
            buffer += data
        return buffer

    def test_tls_stream_returns_exact_response_bytes(self):
        def serve(stream):
            request = self.request(stream)
            while len(request.partition(b"\r\n\r\n")[2]) < 19:
                more = stream.recv(19)
                if not more:
                    break
                request += more
            stream.sendall(HEAD + b"first-")
            time.sleep(0.08)
            stream.sendall(b"second")
            try:
                stream.unwrap()
            except OSError:
                pass
            return request

        result, request = self.exchange(serve, mode="post")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, HEAD + b"first-second")
        self.assertIn(b"Host: egress.test\r\n", request)
        self.assertEqual(request.partition(b"\r\n\r\n")[2], b'{"model":"fixture"}')

    def test_large_post_flushes_under_socket_backpressure(self):
        expected_size = 8 * 1024 * 1024

        def serve(stream):
            time.sleep(0.08)
            body = self.request(stream).partition(b"\r\n\r\n")[2]
            digest = hashlib.sha256(body)
            received = len(body)
            while received < expected_size:
                chunk = stream.recv(65536)
                if not chunk:
                    break
                received += len(chunk)
                digest.update(chunk)
            stream.sendall(HEAD + b"first-second")
            try:
                stream.unwrap()
            except OSError:
                pass
            return received, digest.digest()

        result, received = self.exchange(serve, mode="large-post", timeout=3000)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(received, (expected_size, hashlib.sha256(b"q" * expected_size).digest()))
        self.assertEqual(result.stdout, HEAD + b"first-second")

    def test_complete_response_does_not_wait_for_peer_close(self):
        def hold_open(stream):
            request = self.request(stream)
            stream.sendall(HEAD + b"first-second")
            return request, stream.recv(1)

        result, (request, terminal) = self.exchange(hold_open, mode="finish-at-boundary")
        self.assertTrue(request)
        self.assertEqual(terminal, b"")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, HEAD + b"first-second")

    def test_tls_close_without_notify_reports_failure(self):
        def truncate(stream):
            request = self.request(stream)
            stream.sendall(HEAD + b"first-")
            return request

        result, request = self.exchange(truncate)
        self.assertTrue(request)
        self.assertEqual(result.returncode, 3, result.stderr)

    def test_wrong_name_and_untrusted_chain_send_no_request(self):
        for options in ({"host": "wrong.test"}, {"trusted": False}):
            with self.subTest(options=options):
                result, request = self.exchange(self.request, **options)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(request, b"")
                self.assertEqual(result.stdout, b"")

    def test_transport_owns_the_no_network_trust_policy(self):
        symbols = subprocess.run(["nm", "-u", str(self.binary)], check=True, capture_output=True, timeout=5).stdout
        self.assertIn(b"_SecTrustSetNetworkFetchAllowed", symbols)
        self.assertIn(b"_SecPolicyCreateRevocation", symbols)

    def test_missing_intermediate_does_not_fetch_and_complete_chain_works(self):
        def openssl(*args):
            subprocess.run(["openssl", *args], cwd=self.work, check=True, capture_output=True, timeout=10)

        with socket.socket() as sentinel:
            sentinel.bind(("127.0.0.1", 0))
            sentinel.listen(1)
            sentinel.settimeout(0.25)
            url = f"http://127.0.0.1:{sentinel.getsockname()[1]}"
            (self.work / "intermediate.ext").write_text(
                "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n", encoding="ascii",
            )
            (self.work / "network-hints.ext").write_text(
                "subjectAltName=DNS:egress.test\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n"
                f"authorityInfoAccess=caIssuers;URI:{url}/issuer,OCSP;URI:{url}/status\n"
                f"crlDistributionPoints=URI:{url}/revocation\n", encoding="ascii",
            )
            openssl("req", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=ARTEX Fixture Intermediate",
                    "-keyout", "intermediate.key", "-out", "intermediate.csr")
            openssl("x509", "-req", "-in", "intermediate.csr", "-CA", "ca.pem", "-CAkey", "ca.key",
                    "-CAcreateserial", "-days", "1", "-extfile", "intermediate.ext", "-out", "intermediate.pem")
            openssl("x509", "-req", "-in", "server.csr", "-CA", "intermediate.pem", "-CAkey", "intermediate.key",
                    "-CAcreateserial", "-days", "1", "-extfile", "network-hints.ext", "-out", "network-leaf.pem")
            chain = self.work / "network-chain.pem"
            chain.write_bytes((self.work / "network-leaf.pem").read_bytes() + (self.work / "intermediate.pem").read_bytes())

            missing = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            missing.load_cert_chain(self.work / "network-leaf.pem", self.work / "server.key")
            result, request = self.exchange(self.request, tls_context=missing)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(request, b"")
            self.assertEqual(result.stdout, b"")

            def answer(stream):
                request = self.request(stream)
                stream.sendall(HEAD + b"first-second")
                try:
                    stream.unwrap()
                except OSError:
                    pass
                return request

            complete = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            complete.load_cert_chain(chain, self.work / "server.key")
            result, request = self.exchange(answer, tls_context=complete)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(request.startswith(b"GET /v1/models "))
            self.assertEqual(result.stdout, HEAD + b"first-second")
            with self.assertRaises(TimeoutError):
                sentinel.accept()

    def test_held_tls_handshake_timeout_is_pre_dispatch_failure(self):
        def hold(connection):
            received = bytearray()
            while data := connection.recv(4096):
                received.extend(data)
            return bytes(received)

        result, encrypted_handshake = self.exchange(hold, tls=False, timeout=600)
        self.assertTrue(encrypted_handshake)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout, b"")

    def test_held_tls_handshake_is_cancelled(self):
        def hold(connection):
            while connection.recv(4096):
                pass
            return True

        result, closed = self.exchange(hold, tls=False, mode="cancel-dial")
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertTrue(closed)

    def test_cancellation_and_deadline_close_held_response(self):
        def hold(stream):
            request = self.request(stream)
            stream.sendall(HEAD + b"first-")
            try:
                closed = stream.recv(1) == b""
            except (ConnectionResetError, ssl.SSLEOFError):
                closed = True
            return request, closed

        for options, expected in (({"mode": "cancel-after-chunk"}, 4), ({"timeout": 600}, 5)):
            with self.subTest(options=options):
                result, (request, closed) = self.exchange(hold, **options)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual(result.stdout, HEAD + b"first-")
                self.assertTrue(request.startswith(b"GET /v1/models "))
                self.assertTrue(closed)

    def test_response_cap_stops_delivery(self):
        def serve(stream):
            request = self.request(stream)
            stream.sendall(HEAD + b"first-second")
            return request

        result, request = self.exchange(serve, limit=4)
        self.assertEqual(result.returncode, 6, result.stderr)
        self.assertLessEqual(len(result.stdout), 4)
        self.assertTrue(request)

    def test_direct_failure_does_not_use_configured_proxy(self):
        with socket.socket() as target, socket.socket() as proxy:
            target.bind(("127.0.0.1", 0))
            proxy.bind(("127.0.0.1", 0))
            proxy.listen(1)
            proxy.settimeout(0.2)
            url = f"http://127.0.0.1:{proxy.getsockname()[1]}"
            env = os.environ | {key: url for key in ("HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy")}
            env["NO_PROXY"] = env["no_proxy"] = ""
            result = self.client(target.getsockname()[1], timeout=600, env=env)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(result.stdout, b"")
            with self.assertRaises(TimeoutError):
                proxy.accept()
