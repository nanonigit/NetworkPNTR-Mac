"""Small attachment metadata/rejection fixture on an owned pinned Linux backend."""
import hashlib
import http.client
import json
import os
import platform
import secrets
import time
from urllib.parse import urlencode


def require(condition, label):
    if not condition:
        raise RuntimeError('Attachment state reference contract failed: ' + label)


def multipart(parts):
    if not parts:
        raise ValueError('Empty reference multipart')
    boundary = 'ArtexAttachmentStateFixture'
    body = bytearray()
    for name, data in parts:
        if not name or name in ('.', '..') or '/' in name or '\\' in name or any(ord(char) < 32 or ord(char) == 127 for char in name) or len(name.encode()) > 255 or not isinstance(data, bytes):
            raise ValueError('Invalid reference multipart')
        name = name.replace('"', '%22')
        body.extend((f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\nContent-Type: application/octet-stream\r\n\r\n').encode())
        body.extend(data)
        body.extend(b'\r\n')
        if len(body) > 65536:
            raise ValueError('Reference multipart bound')
    body.extend(f'--{boundary}--\r\n'.encode())
    if len(body) > 65536:
        raise ValueError('Reference multipart bound')
    return 'multipart/form-data; boundary=' + boundary, bytes(body)


class Client:
    def __init__(self):
        self.token = None

    def request(self, method, path, body=None, content_type=None, binary=False):
        connection = http.client.HTTPConnection('127.0.0.1', 8787, timeout=20)
        headers = {'Content-Type': content_type or 'application/json'}
        if self.token:
            headers['Authorization'] = 'Bearer ' + self.token
        try:
            data = body if content_type else json.dumps(body).encode() if body is not None else None
            connection.request(method, path, body=data, headers=headers)
            response = connection.getresponse()
            content = response.read(4 * 1024 * 1024 + 1)
            require(len(content) <= 4 * 1024 * 1024, 'response bound')
            return response.status, content if binary else json.loads(content)
        finally:
            connection.close()

    def api(self, method, path, body=None, expected=200, content_type=None, binary=False):
        status, result = self.request(method, path, body, content_type, binary)
        require(status == expected, 'API status')
        return result


def main():
    if platform.system() != 'Linux' or os.getuid() != 1000 or os.environ.get('ARTEX_DISPOSABLE_REFERENCE') != '1':
        raise RuntimeError('Attachment fixture requires an isolated disposable reference container')
    client = Client()
    for _ in range(120):
        try:
            if client.request('GET', '/api/auth/status')[0] == 200:
                break
        except (OSError, http.client.HTTPException):
            pass
        time.sleep(.5)
    else:
        raise RuntimeError('Attachment reference readiness failed')
    session = client.api('POST', '/api/auth/init', {'password': secrets.token_hex(24), 'setup_token': os.environ['ARTEX_SETUP_TOKEN']})
    client.token = session['token']
    require(not client.api('GET', '/api/conversations')['conversations'] and not client.api('GET', '/api/llm/profiles')['profiles'], 'fresh no-LLM state')
    owned = []
    try:
        conversation = client.api('POST', '/api/conversations', {'agent_key': 'auto', 'title': '', 'llm_profile_id': None})
        identity = conversation['id']
        require(type(identity) is int and identity > 0, 'owned conversation')
        owned.append(identity)
        workspace = f'sessions/conv-{identity}/uploads'
        parts = [('e\u0301.txt', b'\x01'), ('other.bin', b'\x02'), ('empty.txt', b'')]
        content_type, body = multipart(parts)
        uploaded = client.api('POST', f'/api/chat/upload?scope=session&id=conv-{identity}', body, content_type=content_type)['attachments']
        require(len(uploaded) == len(parts), 'metadata count')
        attachments, records = [], []
        for item, (name, data) in zip(uploaded, parts):
            require(item['name'] == name and item['path'] == 'uploads/' + name and item['size'] == len(data), 'exact metadata bytes')
            metadata = {key: item[key] for key in ('name', 'path', 'size')}
            attachments.append(metadata)
            actual = client.api('GET', '/api/workspace/download?' + urlencode({'path': workspace + '/' + name}), binary=True)
            require(actual == data, 'exact Unicode-file content')
            records.append({**metadata, 'sha256': hashlib.sha256(actual).hexdigest()})
        statuses = []
        for message in ('', 'retry text'):
            status, _ = client.request('POST', f'/api/conversations/{identity}/messages', {'message': message, 'attachments': attachments})
            require(status == 503, 'send rejected before agent dispatch')
            statuses.append(status)
        # A removed draft card has no guest delete operation.
        names = [entry['name'] for entry in client.api('GET', '/api/workspace/list?' + urlencode({'path': workspace}))['entries']]
        require(set(names) == {part[0] for part in parts}, 'guest files preserved')
        require(not client.api('GET', f'/api/conversations/{identity}/messages?limit=200')['items'], 'no rejected history')
        other = client.api('POST', '/api/conversations', {'agent_key': 'auto', 'title': 'Native other attachment fixture', 'llm_profile_id': None})['id']
        require(type(other) is int and other > 0, 'other owned conversation')
        owned.append(other)
        result = {'records': records, 'failed_send_statuses': statuses, 'guest_names_after_remove': sorted(names),
                  'history_empty_after_rejections': True, 'owned_files_and_conversation_cleaned': True}
    finally:
        for identity in reversed(owned):
            status, _ = client.request('DELETE', '/api/workspace/delete?' + urlencode({'path': f'sessions/conv-{identity}/uploads'}))
            require(status in (200, 404), 'owned file cleanup')
            require(client.api('DELETE', f'/api/conversations/{identity}')['deleted'] == identity, 'owned conversation cleanup')
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()
