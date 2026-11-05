import copy
import http.client
import socket
import threading
from http.server import HTTPServer
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
import cloud_history_fixture as fixture


class CloudHistoryFixtureTests(unittest.TestCase):
    def setUp(self):
        self.initial = {'role': 'user', 'content': fixture.FIRST}
        self.tool = {'role': 'assistant', 'tool_calls': [fixture.tool_call()]}
        self.result = {'role': 'tool', 'tool_call_id': fixture.CALL_ID, 'content': '1\t' + fixture.WITNESS}
        self.reply = {'role': 'assistant', 'content': fixture.FIRST_REPLY}
        self.resume = {'role': 'user', 'content': fixture.RESUME}

    def test_first_turn_and_restart_digest(self):
        self.assertIsNone(fixture.validate_messages([self.initial], 'first', 1, None))
        digest = fixture.validate_messages([self.initial, self.tool, self.result], 'first', 2, None)
        history = [self.initial, self.tool, self.result, self.reply, self.resume]
        self.assertEqual(fixture.validate_messages(history, 'resume', 1, digest), digest)

    def test_rejects_wrong_scope_and_changed_result(self):
        prefix = [self.initial, self.tool, self.result]
        digest = fixture.validate_messages(prefix, 'first', 2, None)
        for key in ('signature', 'order', 'result', 'argument', 'repeated'):
            history = copy.deepcopy(prefix + [self.reply, self.resume])
            if key == 'signature':
                history[1]['tool_calls'][0]['extra_content']['google']['thought_signature'] = 'wrong'
            elif key == 'order':
                history[1], history[2] = history[2], history[1]
            elif key == 'result':
                history[2]['content'] += ' altered'
            elif key == 'argument':
                history[1]['tool_calls'][0]['function']['arguments'] = '{"file_path":"/etc/passwd"}'
            else:
                history.insert(3, history[2])
            with self.subTest(key=key), self.assertRaises(ValueError):
                fixture.validate_messages(history, 'resume', 1, digest)

    def test_date_reminder_is_filtered_but_arbitrary_user_content_is_rejected(self):
        reminder = {'role': 'user', 'content': "<system-reminder>\n# currentDate\nToday's date is 2026-11-05.\n</system-reminder>"}
        self.assertIsNone(fixture.validate_messages([reminder, self.initial], 'first', 1, None))
        reminder['content'] += '\nextra'
        with self.assertRaises(ValueError):
            fixture.validate_messages([reminder, self.initial], 'first', 1, None)

    def test_partial_request_releases_the_fixture_for_readiness(self):
        accepted = threading.Event()

        class WitnessServer(HTTPServer):
            def get_request(self):
                request = super().get_request()
                accepted.set()
                return request

        with WitnessServer(('127.0.0.1', 0), fixture.Handler) as server:
            server.phase = 'first'
            server.requests = 0
            worker = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.05}, daemon=True)
            worker.start()
            address = server.server_address
            try:
                with socket.create_connection(address, timeout=2) as partial:
                    partial.sendall(b'POST /v1beta/openai/chat/completions HTTP/1.1\r\nHost: localhost\r\n'
                                    b'Authorization: Bearer ' + fixture.KEY.encode() + b'\r\nContent-Length: 20\r\n\r\n{')
                    self.assertTrue(accepted.wait(2))
                    client = http.client.HTTPConnection(*address, timeout=3)
                    try:
                        client.request('GET', '/ready')
                        reply = client.getresponse()
                        self.assertEqual(reply.status, 200)
                        self.assertEqual(reply.read(), b'fixture')
                    finally:
                        client.close()
            finally:
                server.shutdown()
                worker.join(2)
