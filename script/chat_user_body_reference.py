"""Owned persisted user-body cases on a pinned, isolated Linux reference only."""
import http.client
import json
import os
from pathlib import Path
import platform
import sys
import time
from urllib.parse import urlencode

CONTEXT = Path('/state/data/user-body-reference-context.json')


class Client:
    def __init__(self): self.token = None

    def request(self, method, path, body=None, content_type=None):
        connection = http.client.HTTPConnection('127.0.0.1', 8787, timeout=10)
        headers = {'Content-Type': content_type or 'application/json'}
        if self.token: headers['Authorization'] = 'Bearer ' + self.token
        data = body if content_type else json.dumps(body).encode() if body is not None else None
        try:
            connection.request(method, path, data, headers)
            response = connection.getresponse()
            data = response.read(4 * 1024 * 1024 + 1)
            if len(data) > 4 * 1024 * 1024: raise RuntimeError('Reference response bound')
            return response.status, json.loads(data)
        finally:
            connection.close()

    def api(self, method, path, body=None, expected=(200,), content_type=None):
        status, result = self.request(method, path, body, content_type)
        if status not in expected: raise RuntimeError('User-body reference API status')
        return result


def multipart(parts):
    boundary = 'ArtexUserBodyFixture'
    if not parts: raise ValueError('Empty multipart fixture')
    output = bytearray()
    for name, data in parts:
        if not name or name in ('.', '..') or '/' in name or '\\' in name or '"' in name or any(ord(c) < 32 or ord(c) == 127 for c in name) or not isinstance(data, bytes):
            raise ValueError('Invalid fixture file')
        output.extend((f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\nContent-Type: application/octet-stream\r\n\r\n').encode())
        output.extend(data); output.extend(b'\r\n')
        if len(output) > 65536: raise ValueError('Fixture multipart bound')
    output.extend(f'--{boundary}--\r\n'.encode())
    if len(output) > 65536: raise ValueError('Fixture multipart bound')
    return 'multipart/form-data; boundary=' + boundary, bytes(output)


def cleanup(client, ids):
    if any(type(identity) is not int or identity <= 0 for identity in ids) or len(set(ids)) != len(ids):
        raise ValueError('Owned cleanup identities')
    failed = False
    for identity in ids:
        try:
            status, result = client.request('DELETE', f'/api/conversations/{identity}')
            if status != 404 and (status != 200 or type(result.get('deleted')) is not int or result['deleted'] != identity):
                failed = True
        except Exception: failed = True
        try:
            status, _ = client.request('DELETE', '/api/workspace/delete?' + urlencode({'path': f'sessions/conv-{identity}'}))
            if status not in (200, 404): failed = True
        except Exception: failed = True
    if failed: raise RuntimeError('User-body owned cleanup incomplete')


def save_context(context):
    descriptor = os.open(CONTEXT, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as output: json.dump(context, output)


def main(phase):
    if platform.system() != 'Linux' or os.getuid() != 1000 or os.environ.get('ARTEX_DISPOSABLE_REFERENCE') != '1':
        raise RuntimeError('User-body fixture requires an isolated disposable reference')
    if phase not in ('prepare', 'cleanup'): raise ValueError('Fixture phase')
    client = Client()
    if phase == 'cleanup':
        context = json.loads(CONTEXT.read_text()); client.token = context['token']
        cleanup(client, context['ids']); CONTEXT.unlink()
        print(json.dumps({'owned_fixture_removed': True})); return
    if CONTEXT.exists(): raise RuntimeError('Fresh user-body context required')
    password = os.environ['ARTEX_UI_FIXTURE_PASSWORD']
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        try:
            if client.request('GET', '/api/auth/status')[0] == 200: break
        except (OSError, http.client.HTTPException): pass
        time.sleep(.5)
    else: raise RuntimeError('User-body reference readiness')
    session = client.api('POST', '/api/auth/init', {'password': password, 'setup_token': os.environ['ARTEX_SETUP_TOKEN']})
    client.token = session['token']
    if client.api('GET', '/api/conversations')['conversations'] or client.api('GET', '/api/llm/profiles')['profiles']:
        raise RuntimeError('Fresh user-body reference state required')
    context = {'token': client.token, 'ids': []}; save_context(context)
    try:
        profile = client.api('POST', '/api/llm/profiles', {'name': 'Fixture OpenAI edited', 'format': 'openai', 'model': 'fixture-edited',
            'base_url': 'https://api.example.invalid/v1', 'api_key': 'fixture-non-live-credential-0000', 'streaming': False,
            'retry': {'connect': {'attempts': -1, 'interval_ms': 0}}})
        client.api('POST', '/api/llm/profiles/active', {'id': profile['id']})
        parts = [('e\u0301-a6.txt', b'Owned native and pinned browser A6 attachment fixture\n'), ('empty-a6.txt', b'')]
        rows = []
        for title, text, repeated in [
            ('A6 full attachment body', 'A6 **literal**\nFull-body sentinel 🧪', False),
            ('A6 attachment only', '', False),
            ('A6 repeated reference', 'Repeated reference', True),
        ]:
            conversation = client.api('POST', '/api/conversations', {'agent_key': 'auto', 'title': title, 'llm_profile_id': None})
            identity = conversation['id']
            if type(identity) is not int or identity <= 0 or identity in context['ids']: raise RuntimeError('Owned fixture identity')
            context['ids'].append(identity); save_context(context)
            content_type, body = multipart(parts[:1] if repeated else parts)
            uploaded = client.api('POST', f'/api/chat/upload?scope=session&id=conv-{identity}', body, content_type=content_type)['attachments']
            expected = parts[:1] if repeated else parts
            if len(uploaded) != len(expected): raise RuntimeError('Reference upload count')
            metadata = []
            for item, (name, data) in zip(uploaded, expected):
                if item['name'] != name or item['path'] != 'uploads/' + name or item['size'] != len(data): raise RuntimeError('Reference metadata bytes')
                metadata.append({key: item[key] for key in ('name', 'path', 'size')})
            attachments = metadata * 2 if repeated else metadata
            client.api('POST', f'/api/conversations/{identity}/messages', {'message': text, 'attachments': attachments}, expected=(200, 202))
            for _ in range(200):
                history = client.api('GET', f'/api/conversations/{identity}/messages?limit=200')
                if not history.get('running'): break
                time.sleep(.05)
            else: raise RuntimeError('User-body reference idle timeout')
            users = [row for row in history['items'] if row['kind'] == 'user']
            if len(users) != 1 or users[0].get('detail'): raise RuntimeError('Lazy list user-body contract')
            detail = client.api('GET', f'/api/conversations/{identity}/messages/{users[0]["seq"]}')['detail']
            decoded = json.loads(detail)
            if decoded['text'] != text or decoded['attachments'] != attachments: raise RuntimeError('Persisted user-body mismatch')
            rows.append({'title': title, 'text': text, 'attachments': attachments, 'list_omits_detail': True})
        print(json.dumps({'fixture_only': True, 'cases': rows}, indent=2, ensure_ascii=False))
    except Exception:
        cleanup(client, context['ids']); CONTEXT.unlink(); raise


if __name__ == '__main__': main(sys.argv[1] if len(sys.argv) == 2 else '')
