#!/usr/bin/env python3
"""Fixed loopback provider for the disposable cloud2 VM candidate."""
import hashlib
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

FIRST = 'Read the local VM history fixture'
RESUME = 'Continue the saved VM history fixture'
FIRST_REPLY = 'VM fixture tool result accepted'
RESUME_REPLY = 'VM fixture saved history accepted'
MODEL = 'fixture-vm-history-model'
KEY = 'synthetic-vm-history-key'
CALL_ID = 'call-vm-read-witness'
SIGNATURE = 'opaque+/vm-history-signature=='
READ_PATH = '/run/artex-cloud-history-read.txt'
WITNESS = 'controlled-guest-only-tool-result'
RESULT_DIGEST = Path('/state/home/cloud-history-result.sha256')
REMINDER = re.compile(r"<system-reminder>\n# currentDate\nToday's date is \d{4}-\d{2}-\d{2}\.\n</system-reminder>")


def tool_call():
    return {'id': CALL_ID, 'type': 'function',
            'function': {'name': 'Read', 'arguments': json.dumps({'file_path': READ_PATH})},
            'extra_content': {'google': {'thought_signature': SIGNATURE}}}


def require(condition):
    if not condition:
        raise ValueError('unexpected fixed history')


def validate_messages(messages, phase, request, previous_digest):
    require(isinstance(messages, list) and all(isinstance(message, dict) for message in messages))
    selected = [message for message in messages
                if message.get('role') != 'system'
                and not (message.get('role') == 'user' and isinstance(message.get('content'), str)
                         and REMINDER.fullmatch(message['content']))]
    roles = [message.get('role') for message in selected]
    if (phase, request) == ('first', 1):
        require(roles == ['user'] and selected[0].get('content') == FIRST)
        return None
    require((phase, request) in {('first', 2), ('resume', 1)})
    require(roles == (['user', 'assistant', 'tool'] if phase == 'first'
                      else ['user', 'assistant', 'tool', 'assistant', 'user']))
    require(selected[0].get('content') == FIRST)
    calls = selected[1].get('tool_calls')
    require(isinstance(calls, list) and len(calls) == 1 and isinstance(calls[0], dict))
    call = calls[0]
    function = call.get('function')
    require(call.get('id') == CALL_ID and call.get('type') == 'function'
            and call.get('extra_content') == tool_call()['extra_content'] and isinstance(function, dict))
    arguments = function.get('arguments')
    require(function.get('name') == 'Read' and isinstance(arguments, str)
            and json.loads(arguments) == {'file_path': READ_PATH})
    result = selected[2].get('content')
    require(selected[2].get('tool_call_id') == CALL_ID and isinstance(result, str) and WITNESS in result)
    digest = hashlib.sha256(result.encode()).hexdigest()
    if phase == 'resume':
        require(selected[3].get('content') == FIRST_REPLY and selected[4].get('content') == RESUME
                and digest == previous_digest)
    return digest


def stream_response(delta, reason):
    def frame(payload, finish):
        return 'data: ' + json.dumps({'choices': [{'index': 0, 'delta': payload, 'finish_reason': finish}]}) + '\n\n'
    return (frame(delta, None) + frame({}, reason) + 'data: [DONE]\n\n').encode()


class Handler(BaseHTTPRequestHandler):
    timeout = 1.0

    def log_message(self, *_args):
        pass

    def reply(self, status, content_type, body):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.reply(200 if self.path == '/ready' else 404, 'text/plain', b'fixture')

    def do_POST(self):
        self.server.requests += 1
        request = self.server.requests
        phase = self.server.phase
        try:
            require(self.path == '/v1beta/openai/chat/completions'
                    and self.headers.get('Authorization') == 'Bearer ' + KEY)
            size = int(self.headers.get('Content-Length', 0))
            require(0 < size <= 2 * 1024 * 1024)
            body = json.loads(self.rfile.read(size))
            require(isinstance(body, dict) and body.get('model') == MODEL and body.get('stream') is True)
            digest = validate_messages(body.get('messages'), phase, request, self.server.previous_digest)
            if phase == 'first' and request == 1:
                call = tool_call()
                call['index'] = 0
                response = stream_response({'tool_calls': [call]}, 'tool_calls')
            else:
                if phase == 'first':
                    with RESULT_DIGEST.open('x') as state:
                        state.write(digest + '\n')
                reply = FIRST_REPLY if phase == 'first' else RESUME_REPLY
                response = stream_response({'content': reply}, 'stop')
        except (ValueError, OSError):
            print(f'ARTEX_CLOUD_HISTORY_REJECTED phase={phase} request={request}', flush=True)
            self.reply(400, 'application/json', b'{"error":"fixed history rejected"}')
            return
        self.reply(200, 'text/event-stream', response)
        if digest is not None:
            print(f'ARTEX_CLOUD_HISTORY_ACCEPTED phase={phase} requests={request}', flush=True)


def main():
    phase = sys.argv[1]
    require(phase in {'first', 'resume'})
    require(Path(READ_PATH).exists() == (phase == 'first'))
    with HTTPServer(('127.0.0.1', 8791), Handler) as server:
        server.phase = phase
        server.requests = 0
        server.previous_digest = RESULT_DIGEST.read_text().strip() if phase == 'resume' else None
        if phase == 'resume':
            require(re.fullmatch('[0-9a-f]{64}', server.previous_digest))
        print(f'ARTEX_CLOUD_HISTORY_READY phase={phase}', flush=True)
        server.serve_forever()


if __name__ == '__main__':
    main()
