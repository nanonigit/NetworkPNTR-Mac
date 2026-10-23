"""Finite chat comparison inside the disposable reference container only; no AI turns."""
import json
import os
import platform
import secrets
import time
import urllib.error
import urllib.request


def request(method, path, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request('http://127.0.0.1:8787' + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def require(condition, label):
    if not condition:
        raise RuntimeError('Chat reference contract failed: ' + label)


def main():
    if platform.system() != 'Linux' or os.getuid() != 1000 or os.environ.get('ARTEX_DISPOSABLE_REFERENCE') != '1':
        raise RuntimeError('Chat fixture requires an isolated disposable reference container')
    for _ in range(120):
        try:
            if request('GET', '/api/auth/status')[0] == 200:
                break
        except (OSError, ValueError):
            pass
        time.sleep(.5)
    else:
        raise RuntimeError('Chat reference readiness failed')
    status, session = request('POST', '/api/auth/init', {
        'password': secrets.token_hex(24), 'setup_token': os.environ['ARTEX_SETUP_TOKEN']})
    require(status == 200 and bool(session.get('token')), 'setup')
    token = session['token']


    def api(method, path, body=None, expected=200):
        status, value = request(method, path, body, token)
        require(status == expected, method + ' ' + path)
        return value


    require(not api('GET', '/api/conversations')['conversations'], 'fresh conversations')
    profile = {'name': 'Chat reference profile', 'format': 'openai', 'model': 'fixture-no-request',
               'base_url': 'https://api.example.invalid/v1', 'api_key': 'fixture-non-live-credential-0000'}
    profile_id = api('POST', '/api/llm/profiles', profile)['id']
    key = sorted(agent['key'] for agent in api('GET', '/api/agents')['agents'])[0]
    created = api('POST', '/api/conversations', {'agent_key': key, 'title': 'Native chat fixture', 'llm_profile_id': profile_id})
    identity = created['id']
    route = '/api/conversations/' + str(identity)
    require(created.get('llm_profile_id') == profile_id, 'created profile')
    renamed = api('PATCH', route, {'title': 'Native chat renamed'})
    pinned = api('PATCH', route, {'pinned': True})
    unpinned = api('PATCH', route, {'pinned': False})
    api('PATCH', route + '/profile', {'llm_profile_id': None})
    require(api('GET', '/api/conversations')['conversations'][0].get('llm_profile_id') is None, 'clear profile')
    api('PATCH', route + '/profile', {'llm_profile_id': profile_id})
    require(api('GET', '/api/conversations')['conversations'][0].get('llm_profile_id') == profile_id, 'restore profile')
    history = api('GET', route + '/messages?limit=200')
    delta = api('GET', route + '/messages?since=0')
    detail = api('GET', route + '/messages/9999999')
    stop = api('POST', route + '/stop', {})
    require(not history.get('running') and not delta.get('running'), 'idle transcript')
    api('POST', route + '/messages', {'message': ''}, expected=400)
    api('PATCH', route + '/profile', {'llm_profile_id': 9999999}, expected=400)
    batch = api('POST', '/api/conversations/delete/batch', {'ids': [identity, 9999999, identity]})['items']
    results = {item['id']: item['ok'] for item in batch}
    require(len(batch) == 2 and results.get(identity) is True and results.get(9999999) is False, 'partial batch')
    other = api('POST', '/api/conversations', {'agent_key': key, 'title': 'Native chat cleanup', 'llm_profile_id': None})
    require(api('DELETE', '/api/conversations/' + str(other['id']))['deleted'] == other['id'], 'single delete')
    require(not api('GET', '/api/conversations')['conversations'], 'cleanup')
    print(json.dumps({'created_title': created['title'], 'renamed_title': renamed['title'],
        'pin_roundtrip': pinned.get('pinned') is True and unpinned.get('pinned') is False,
        'profile_clear_restore': True, 'empty_history': not history.get('items'), 'empty_delta': not delta.get('items'),
        'missing_detail_empty': not detail.get('detail'), 'idle_stop': stop['status'],
        'empty_send_status': 400, 'invalid_profile_status': 400, 'batch_existing_ok': results[identity],
        'batch_missing_ok': results[9999999], 'batch_deduplicated_count': len(batch),
        'single_delete_and_cleanup': True}, sort_keys=True))


if __name__ == '__main__':
    main()
