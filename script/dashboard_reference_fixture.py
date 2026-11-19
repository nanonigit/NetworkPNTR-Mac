"""Runs in the disposable reference container; prints only fixture data, never auth."""
import json
import os
import sys
import time
import urllib.request



def request(method, path, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request('http://127.0.0.1:8787' + path, method=method, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)


if sys.argv[1] == 'prepare':
    for _ in range(120):
        try:
            if request('GET', '/api/auth/status')['initialized'] is False:
                break
        except (OSError, ValueError):
            pass
        time.sleep(.5)
    else:
        raise SystemExit('Reference readiness failed')
    session = request('POST', '/api/auth/init', {'password': os.environ['DASHBOARD_FIXTURE_PASSWORD'], 'setup_token': os.environ['ARTEX_SETUP_TOKEN']})
    token = session['token']
    active = request('POST', '/api/llm/profiles', {'name': 'Fixture OpenAI edited', 'format': 'openai', 'model': 'fixture-edited', 'api_key': 'fixture-non-live-credential-0000'}, token)
    request('POST', '/api/llm/profiles/active', {'id': active['id']}, token)
    print('{"prepared":true}')
else:
    for _ in range(120):
        try:
            if request('GET', '/api/auth/status')['initialized'] is True:
                break
        except (OSError, ValueError):
            pass
        time.sleep(.5)
    else:
        raise SystemExit('Reference restart readiness failed')
    # The frozen browser backend uses its original protocol username.
    # Keep this independent of the native app's display name.
    token = request('POST', '/api/auth/login', {'username': 'ARTEX', 'password': os.environ['DASHBOARD_FIXTURE_PASSWORD']})['token']
    def get(path):
        return request('GET', path, token=token)
    print(json.dumps({'tasks': get('/api/tasks')['tasks'], 'fast': {
        'findings': get('/api/exploration/findings'), 'stats': get('/api/stats'), 'settings': get('/api/settings'),
        'pending': get('/api/intercept/pending')['pending'], 'activity': get('/api/exploration/activity?limit=30')['items'],
        'conversations': get('/api/tokens/conversations')}, 'slow': {
        'traffic': get('/api/traffic?page=0&size=50')['exchanges'], 'asset_counts': get('/api/assets/counts'),
        'profiles': get('/api/llm/profiles')['profiles'], 'usage': get('/api/tokens/usage?days=365')}}))
