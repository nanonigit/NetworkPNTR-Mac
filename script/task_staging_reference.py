"""Synthetic staging exercise inside a fresh isolated pinned reference container."""
import hashlib
import json
import os
import platform
import secrets
import subprocess
import time
from urllib.parse import urlencode

from chat_upload_contract_fixture import Client, Multipart, require

DRAFT = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
INPUT_NAMES = ['fixture.bin', 'empty.txt', 'fixture.bin', '日本-e\u0301.txt']
FIRST_NAMES = ['fixture.bin', 'empty.txt', 'fixture-1.bin', '日本-e\u0301.txt']
REPEAT_NAMES = ['fixture-2.bin', 'empty-1.txt', 'fixture-3.bin', '日本-e\u0301-1.txt']
CONTENTS = [bytes(index % 256 for index in range(70001)), b'', b'second synthetic attachment\n',
            bytes(index % 251 for index in range(1280))]


def validate_attachment(item, name, size):
    require(isinstance(item, dict), 'staging metadata object')
    require(item.get('name') == name and item.get('path') == 'uploads/' + name, 'staging name/path')
    require(type(item.get('size')) is int and item['size'] == size, 'staging size')
    require(item.get('abs') == '/state/data/drafts/' + DRAFT + '/uploads/' + name, 'staging absolute path')
    return item


class StagingClient(Client):
    def upload_staging(self):
        import http.client
        multipart = Multipart([(name, len(data), lambda data=data: iter([data]))
                               for name, data in zip(INPUT_NAMES, CONTENTS)])
        connection = http.client.HTTPConnection('127.0.0.1', 8787, timeout=60)
        try:
            connection.putrequest('POST', '/api/chat/upload?scope=staging&id=' + DRAFT)
            connection.putheader('Content-Type', multipart.content_type)
            connection.putheader('Content-Length', str(multipart.length))
            connection.putheader('Authorization', 'Bearer ' + self.token)
            connection.endheaders()
            for block in multipart.chunks():
                connection.send(block)
            response = connection.getresponse()
            content = response.read(4 * 1024 * 1024 + 1)
            require(response.status == 200 and len(content) <= 4 * 1024 * 1024, 'staging upload response')
            return json.loads(content)['attachments']
        finally:
            connection.close()


def verify(client, attachments):
    records = []
    for item, expected in zip(attachments, CONTENTS):
        path = 'drafts/' + DRAFT + '/' + item['path']
        data = client.api('GET', '/api/workspace/download?' + urlencode({'path': path}), binary=True)
        require(data == expected, 'staging full readback bytes')
        records.append({'name': item['name'], 'path': item['path'], 'size': item['size'],
                        'sha256': hashlib.sha256(data).hexdigest()})
    return records


def main():
    require(platform.system() == 'Linux' and os.getuid() == 1000 and
            os.environ.get('ARTEX_DISPOSABLE_REFERENCE') == '1', 'disposable staging reference environment')
    client = StagingClient()
    for _ in range(120):
        try:
            status, value = client.request('GET', '/api/auth/status')
            if status == 200:
                break
        except (OSError, ValueError):
            pass
        time.sleep(.5)
    else:
        raise RuntimeError('Staging reference readiness failed')
    require(value.get('initialized') is False and value.get('setup_token_required') is True, 'fresh reference authentication')
    session = client.api('POST', '/api/auth/init', {'password': secrets.token_hex(24),
                                                 'setup_token': os.environ['ARTEX_SETUP_TOKEN']})
    client.token = session['token']
    batches, records = [], []
    for names in [FIRST_NAMES, REPEAT_NAMES]:
        attachments = client.upload_staging()
        require(isinstance(attachments, list) and len(attachments) == 4, 'complete staging response')
        for item, name, content in zip(attachments, names, CONTENTS):
            validate_attachment(item, name, len(content))
        records.extend(verify(client, attachments))
        batches.append(attachments)
    verify(client, batches[0])
    normalized = [[{**item, 'abs': '<draft>/uploads/' + item['name']} for item in batch] for batch in batches]
    # This reviewed oracle is extracted from the same pinned browser source, not a port.
    result = subprocess.run(['node', '/tmp/t7-manifest-oracle.cjs'], input=json.dumps(normalized).encode(),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=10)
    require(result.returncode == 0 and len(result.stdout) <= 65536, 'pinned manifest oracle')
    manifests = json.loads(result.stdout)
    require(set(manifests) == {'englishManifest', 'japaneseManifest'} and
            all(isinstance(value, str) for value in manifests.values()), 'manifest schema')
    print(json.dumps({'records': records, **manifests, 'originalFilesPreserved': True}, ensure_ascii=False))


if __name__ == '__main__':
    main()
