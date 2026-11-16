"""Exercise the actual MCP helper against a caller-provided disposable broker."""
import json
import errno
import os
import select
import socket
import subprocess
import sys
import time


def run(binary, connection):
    child = subprocess.Popen([binary, '--connection-file', connection], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    pending = bytearray()

    def send(message):
        child.stdin.write(json.dumps(message).encode() + b'\n')
        child.stdin.flush()

    def reply(request_id):
        while b'\n' not in pending:
            if not select.select([child.stdout], [], [], 5)[0]:
                raise AssertionError('MCP response timeout')
            chunk = os.read(child.stdout.fileno(), 4096)
            if not chunk:
                raise AssertionError('MCP closed before response')
            pending.extend(chunk)
            if len(pending) > 65536:
                raise AssertionError('Unexpected response size')
        line, _, remaining = pending.partition(b'\n')
        pending[:] = remaining
        message = json.loads(line)
        assert message['id'] == request_id
        return message

    def request(request_id, method, params):
        send({'jsonrpc': '2.0', 'id': request_id, 'method': method, 'params': params})
        return reply(request_id)

    try:
        for request_id in [1, *range(20, 32)]:
            assert 'error' in request(request_id, 'tools/call',
                                      {'name': 'artex_agents_list', 'arguments': {}})
        initialized = request(2, 'initialize', {
            'protocolVersion': '2025-06-18', 'capabilities': {},
            'clientInfo': {'name': 'artex-disposable-test', 'version': '1.0'}})
        assert initialized['result']['serverInfo']['name'] == 'ARTEX Mac'
        send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        tools = request(3, 'tools/list', {})['result']['tools']
        assert {tool['name'] for tool in tools} == {'artex_agents_list', 'artex_task_status'}
        assert all(tool['annotations']['readOnlyHint'] for tool in tools)
        result = request(4, 'tools/call', {'name': 'artex_agents_list', 'arguments': {}})['result']
        assert not result.get('isError', False)
        agents = json.loads(result['content'][0]['text'])
        assert agents[0]['key'] == 'worker'
        assert set(agents[0]) == {'key', 'name', 'enabled'}
        result = request(9, 'tools/call', {'name': 'artex_task_status', 'arguments': {'id': '9007199254740993'}})['result']
        assert not result.get('isError', False)
        status = json.loads(result['content'][0]['text'])
        assert status['id'] == '9007199254740993'
        assert status['inputTokens'] == 9007199254740993
        assert set(status) == {'id', 'status', 'paused', 'queued', 'inputTokens', 'outputTokens'}
        invalid = request(5, 'tools/call', {'name': 'artex_agents_list', 'arguments': {'url': 'https://example.invalid'}})
        assert invalid['error']['code'] == -32602
        denied = request(6, 'tools/call', {'name': 'artex_task_status', 'arguments': {'id': '7'}})['result']
        assert denied['isError'] is True
        invalid = request(7, 'tools/call', {'name': 'artex_task_status', 'arguments': {'id': '0007'}})
        assert invalid['error']['code'] == -32602
        invalid = request(8, 'tools/call', {'name': 'artex_agent_start', 'arguments': {}})
        assert invalid['error']['code'] == -32602
        for index in range(13):
            request_id = 200 + index
            send({'jsonrpc': '2.0', 'id': request_id, 'method': 'tools/call',
                  'params': {'name': 'artex_agents_list', 'arguments': {}}})
            if index:
                time.sleep(0.1)
            send({'jsonrpc': '2.0', 'method': 'notifications/cancelled',
                  'params': {'requestId': request_id}})
            assert request(300 + index, 'ping', {})['result'] == {}
        for index in range(9):
            send({'jsonrpc': '2.0', 'id': 1000 + index, 'method': 'tools/call',
                  'params': {'name': 'artex_agents_list', 'arguments': {}}})
        assert 'error' in reply(1008)
        for index in range(8):
            send({'jsonrpc': '2.0', 'method': 'notifications/cancelled',
                  'params': {'requestId': 1000 + index}})
        recovered = False
        for index in range(50):
            ping = request(1200 + index, 'ping', {})
            if 'result' in ping:
                recovered = True
                break
            time.sleep(0.02)
        assert recovered, ping
        with open(connection, encoding='utf-8') as source:
            socket_path = json.load(source)['socketPath']
        for _ in range(200):
            deadline = time.monotonic() + 2
            while True:
                try:
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as aborted:
                        aborted.settimeout(2)
                        aborted.connect(socket_path)
                    break
                except OSError as error:
                    if error.errno not in (errno.ECONNREFUSED, errno.EAGAIN) or time.monotonic() >= deadline:
                        raise
                    time.sleep(0.005)
        result = request(400, 'tools/call', {'name': 'artex_task_status', 'arguments': {'id': '9007199254740993'}})['result']
        assert json.loads(result['content'][0]['text'])['inputTokens'] == 9007199254740993
        child.stdin.close()
        assert child.wait(timeout=5) == 0
        assert not pending
        assert child.stdout.read() == b''
        assert child.stderr.read() == b''
        print('PASS stdio initialization discovery typed-read invalid-input scope-denial repeated-cancellation clean-EOF')
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=5)


if __name__ == '__main__':
    run(*sys.argv[1:])
