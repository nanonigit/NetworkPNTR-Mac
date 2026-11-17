"""Synthetic uploads inside the disposable pinned reference container only."""
import hashlib
import http.client
import json
import os
import platform
import re
import secrets
import time
from urllib.parse import urlencode

MAX_BODY = 128 * 1024 * 1024
BOUNDARY = 'NetworkPNTRMac-' + '0' * 36
CHUNK = 65536


def zero_blocks(size):
    while size:
        count = min(size, CHUNK)
        yield bytes(count)
        size -= count


class Multipart:
    def __init__(self, parts, boundary=BOUNDARY):
        if not parts or not re.fullmatch(r'[A-Za-z0-9_-]{1,70}', boundary):
            raise ValueError('Invalid synthetic multipart framing')
        self.parts = []
        self.length = 0
        for name, size, blocks in parts:
            if not name or len(name.encode('utf-8')) > 255 or '\0' in name or size < 0 or size > MAX_BODY + 1:
                raise ValueError('Invalid synthetic multipart part')
            escaped = name.replace('\r', '%0D').replace('\n', '%0A').replace('"', '%22')
            header = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{escaped}"\r\n'
                      'Content-Type: application/octet-stream\r\n\r\n').encode('utf-8')
            self.parts.append((header, size, blocks))
            self.length += len(header) + size + 2
        self.ending = f'--{boundary}--\r\n'.encode('ascii')
        self.length += len(self.ending)
        self.content_type = 'multipart/form-data; boundary=' + boundary

    def chunks(self):
        for header, size, blocks in self.parts:
            yield header
            count = 0
            for block in blocks():
                if not isinstance(block, bytes):
                    raise RuntimeError('Synthetic multipart content length/type mismatch')
                count += len(block)
                if count > size:
                    raise RuntimeError('Synthetic multipart content length mismatch')
                for offset in range(0, len(block), CHUNK):
                    yield block[offset:offset + CHUNK]
            if count != size:
                raise RuntimeError('Synthetic multipart content length mismatch')
            yield b'\r\n'
        yield self.ending


class Client:
    def __init__(self):
        self.token = None

    def request(self, method, path, body=None, binary=False):
        connection = http.client.HTTPConnection('127.0.0.1', 8787, timeout=60)
        headers = {'Content-Type': 'application/json'}
        if self.token:
            headers['Authorization'] = 'Bearer ' + self.token
        try:
            data = json.dumps(body).encode() if body is not None else None
            connection.request(method, path, body=data, headers=headers)
            response = connection.getresponse()
            content = response.read(4 * 1024 * 1024 + 1)
            require(len(content) <= 4 * 1024 * 1024, 'finite response bound')
            return response.status, content if binary else json.loads(content)
        finally:
            connection.close()

    def api(self, method, path, body=None, expected=200, binary=False):
        status, value = self.request(method, path, body, binary)
        require(status == expected, 'API status')
        return value

    def digest(self, path, expected_size):
        require(isinstance(expected_size, int) and 0 <= expected_size <= MAX_BODY, 'download size bound')
        connection = http.client.HTTPConnection('127.0.0.1', 8787, timeout=60)
        try:
            headers = {'Connection': 'close', 'Accept-Encoding': 'identity'}
            if self.token:
                headers['Authorization'] = 'Bearer ' + self.token
            connection.request('GET', path, headers=headers)
            response = connection.getresponse()
            fields = {}
            for name, value in response.getheaders():
                name = name.lower()
                require(name not in fields or name not in ('content-length', 'transfer-encoding', 'content-encoding'), 'duplicate download framing')
                fields[name] = value.strip()
            length = fields.get('content-length', '')
            require(response.status == 200 and re.fullmatch(r'[0-9]+', length) is not None and int(length) == expected_size,
                    'download status and length')
            require('transfer-encoding' not in fields and fields.get('content-encoding', 'identity').lower() == 'identity', 'download encoding')
            count, digest = 0, hashlib.sha256()
            while True:
                block = response.read(CHUNK)
                if not block:
                    break
                count += len(block)
                require(len(block) <= CHUNK and count <= expected_size, 'download extra content')
                digest.update(block)
            require(count == expected_size, 'download short content')
            return {'downloaded_size': count, 'sha256': digest.hexdigest(), 'full_content_hash_verified': True}
        finally:
            connection.close()

    def upload(self, identity, multipart):
        connection = http.client.HTTPConnection('127.0.0.1', 8787, timeout=60)
        try:
            connection.putrequest('POST', f'/api/chat/upload?scope=session&id=conv-{identity}')
            connection.putheader('Content-Type', multipart.content_type)
            connection.putheader('Content-Length', str(multipart.length))
            connection.putheader('Authorization', 'Bearer ' + self.token)
            connection.putheader('Connection', 'close')
            connection.endheaders()
            try:
                for chunk in multipart.chunks():
                    connection.send(chunk)
            except (BrokenPipeError, ConnectionResetError):
                # Preserve a framed early backend rejection rather than printing its body.
                pass
            response = connection.getresponse()
            content = response.read(4 * 1024 * 1024 + 1)
            require(len(content) <= 4 * 1024 * 1024, 'upload response bound')
            return response.status, json.loads(content)
        finally:
            connection.close()


def require(condition, label):
    if not condition:
        raise RuntimeError('Upload reference contract failed: ' + label)


def main():
    if platform.system() != 'Linux' or os.getuid() != 1000 or os.environ.get('ARTEX_DISPOSABLE_REFERENCE') != '1':
        raise RuntimeError('Upload fixture requires an isolated disposable reference container')
    client = Client()
    for _ in range(120):
        try:
            if client.request('GET', '/api/auth/status')[0] == 200:
                break
        except (OSError, http.client.HTTPException):
            pass
        time.sleep(.5)
    else:
        raise RuntimeError('Upload reference readiness failed')
    session = client.api('POST', '/api/auth/init', {'password': secrets.token_hex(24), 'setup_token': os.environ['ARTEX_SETUP_TOKEN']})
    client.token = session['token']
    require(not client.api('GET', '/api/conversations')['conversations'], 'fresh conversations')
    conversation = client.api('POST', '/api/conversations', {'agent_key': 'auto', 'title': 'Native upload transport fixture', 'llm_profile_id': None})
    identity = conversation['id']
    require(isinstance(identity, int) and identity > 0, 'owned conversation')
    workspace = 'sessions/conv-' + str(identity) + '/uploads'
    try:
        contents = [bytes(index % 256 for index in range(70001)), b'', b'second synthetic attachment\n']
        names = ['fixture.bin', 'empty.txt', 'fixture.bin']
        parts = [(name, len(data), lambda data=data: iter([data])) for name, data in zip(names, contents)]
        status, value = client.upload(identity, Multipart(parts))
        require(status == 200, 'small multipart status')
        attachments = value['attachments']
        require([item['name'] for item in attachments] == ['fixture.bin', 'empty.txt', 'fixture-1.bin'], 'duplicate ordering')
        records = []
        for item, data in zip(attachments, contents):
            require(item['path'] == 'uploads/' + item['name'] and item['size'] == len(data), 'attachment metadata')
            path = 'sessions/conv-' + str(identity) + '/' + item['path']
            actual = client.api('GET', '/api/workspace/download?' + urlencode({'path': path}), binary=True)
            require(actual == data, 'exact small-file bytes')
            records.append({'name': item['name'], 'path': item['path'], 'size': item['size'], 'sha256': hashlib.sha256(actual).hexdigest()})
        overhead = Multipart([('limit.bin', 0, lambda: iter([]))]).length
        size = MAX_BODY - overhead
        exact = Multipart([('limit.bin', size, lambda: zero_blocks(size))])
        require(exact.length == MAX_BODY, 'exact body length')
        status, value = client.upload(identity, exact)
        require(status == 200 and value['attachments'][0]['name'] == 'limit.bin' and value['attachments'][0]['size'] == size, 'exact limit accepted')
        entries = client.api('GET', '/api/workspace/list?' + urlencode({'path': workspace}))['entries']
        require(next(item['size'] for item in entries if item['name'] == 'limit.bin') == size, 'persisted size')
        downloaded = client.digest('/api/workspace/download?' + urlencode({'path': workspace + '/limit.bin'}), size)
        expected_hash = hashlib.sha256()
        for block in zero_blocks(size):
            expected_hash.update(block)
        require(downloaded['sha256'] == expected_hash.hexdigest(), 'large file full hash')
        oversized = Multipart([('limit.bin', size + 1, lambda: zero_blocks(size + 1))])
        require(oversized.length == MAX_BODY + 1, 'over body length')
        require(client.upload(identity, oversized)[0] == 400, 'over body rejected')
        after = client.api('GET', '/api/workspace/list?' + urlencode({'path': workspace}))['entries']
        require(not any(item['name'] == 'limit-1.bin' for item in after), 'no rejected duplicate')
        require(next(item['size'] for item in after if item['name'] == 'limit.bin') == size, 'original preserved')
        result = {'records': records, 'limit': {'body_bytes': MAX_BODY, 'file_size': size, 'persisted_size': size,
                  'over_limit_rejected': True, 'duplicate_after_rejection': False, **downloaded}, 'owned_files_and_conversation_cleaned': True}
    finally:
        client.api('DELETE', '/api/workspace/delete?' + urlencode({'path': workspace}))
        require(client.api('DELETE', '/api/conversations/' + str(identity))['deleted'] == identity, 'conversation cleanup')
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
