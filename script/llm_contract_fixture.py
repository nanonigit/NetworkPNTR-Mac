"""Runs only inside the disposable reference container; emits no credentials."""
import json
import os
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


for _ in range(120):
    try:
        if request('GET', '/api/auth/status')[0] == 200:
            break
    except (OSError, ValueError):
        pass
    time.sleep(.5)
else:
    raise SystemExit('Reference readiness failed')
status, session = request('POST', '/api/auth/init', {'password': secrets.token_hex(24), 'setup_token': os.environ['ARTEX_SETUP_TOKEN']})
assert status == 200 and session.get('token'), 'Reference setup failed'
token = session['token']


def call(method, path, body=None, status=200):
    actual, result = request(method, path, body, token)
    assert actual == status, 'Reference operation failed: ' + method + ' ' + path
    return result


assert not call('GET', '/api/llm/profiles')['profiles']
negative = {'provider': 'anthropic', 'model': 'fixture-no-external-request', 'api_key': '', 'base_url': '', 'proxy': ''}
assert call('POST', '/api/llm/models', negative)['ok'] is False
assert call('POST', '/api/llm/test', dict(negative, streaming=True, thinking_type='', reasoning_effort='', session_header_key=''))['ok'] is False
zero = {'attempts': 0, 'interval_ms': 0}
retry = {'connect': {'attempts': -1, 'interval_ms': 0}, 'empty': {'attempts': 2, 'interval_ms': 1234}, 'stream': {'attempts': 1, 'interval_ms': 500}}
a = {'name': 'Fixture OpenAI', 'model': 'fixture-no-request', 'format': 'openai', 'base_url': 'https://api.example.invalid/v1', 'proxy': '', 'api_key': 'fixture-non-live-credential-0000', 'rate_per_second': 2.5, 'rate_per_minute': 30, 'context_window_k': 64, 'priority': 3, 'pool_exclude': False, 'streaming': False, 'max_tokens': 256, 'max_tokens_field': 'max_completion_tokens', 'thinking_type': 'enabled', 'reasoning_effort': 'high', 'session_header_key': 'X-Artex-Session', 'retry': retry}
a_id = call('POST', '/api/llm/profiles', a)['id']
b = {'name': 'Fixture Anthropic', 'model': 'fixture-anthropic', 'format': 'anthropic', 'streaming': True}
b_id = call('POST', '/api/llm/profiles', b)['id']
c = {'name': 'Fixture Responses', 'model': 'fixture-responses', 'format': 'openai-responses', 'priority': 9, 'pool_exclude': True, 'streaming': True}
c_id = call('POST', '/api/llm/profiles', c)['id']
created = call('GET', '/api/llm/profiles')['profiles']
assert len(created) == 3
original = next(p for p in created if p['id'] == str(a_id))
assert original.get('api_key_hint') and not original['is_default'] and original['streaming'] is False
edited = dict(a, id=a_id, api_key='', name='Fixture OpenAI edited', model='fixture-edited', rate_per_minute=60)
call('POST', '/api/llm/profiles', edited)
updated = next(p for p in call('GET', '/api/llm/profiles')['profiles'] if p['id'] == str(a_id))
assert updated['api_key_hint'] == original['api_key_hint'] and updated['streaming'] is False
call('POST', '/api/llm/profiles/active', {'id': a_id})
call('DELETE', '/api/llm/profiles/' + str(a_id), status=409)
call('PUT', '/api/settings', {'llm_pool_enabled': True, 'llm_pool_bind_fallback': True})
pool = call('GET', '/api/llm/pool')
assert pool['enabled'] and pool['bind_fallback'] and pool['chain'][0]['profile_id'] == str(a_id)
assert any(p['profile_id'] == str(c_id) and p['excluded'] for p in pool['chain'])
call('POST', '/api/llm/pool/reset', {'id': a_id})
call('POST', '/api/llm/pool/reset', {'id': 0})
policy = {'connect': {'attempts': 4, 'interval_ms': 1000}, 'empty': {'attempts': -1, 'interval_ms': 0}, 'stream': {'attempts': 2, 'interval_ms': 500}, 'breaker': {'attempts': 3, 'interval_ms': 60000}, 'intent': {'attempts': 1, 'interval_ms': 3000}}
assert call('POST', '/api/llm/retry-policy', policy) == policy
assert call('GET', '/api/llm/retry-policy') == policy
call('DELETE', '/api/llm/profiles/' + str(b_id))
call('DELETE', '/api/llm/profiles/' + str(c_id))
remaining = call('GET', '/api/llm/profiles')['profiles']
assert len(remaining) == 1 and remaining[0]['is_default']
p = remaining[0]
keys = ['name', 'format', 'model', 'is_default', 'rate_per_second', 'rate_per_minute', 'context_window_k', 'thinking_type', 'reasoning_effort', 'priority', 'pool_exclude', 'streaming', 'max_tokens', 'max_tokens_field', 'session_header_key', 'retry']
profile = {key: p[key] for key in keys}
profile.update(base_url=p.get('base_url', ''), proxy=p.get('proxy', ''), key_present=bool(p.get('api_key_hint')))
print(json.dumps({'profile': profile, 'retry_policy': policy, 'rotation_enabled': pool['enabled'], 'bind_fallback': pool['bind_fallback'], 'created_formats': sorted(p['format'] for p in created), 'active_delete_status': 409, 'inactive_delete_remaining': len(remaining), 'blank_key_preserved': True, 'missing_key_models_rejected': True, 'missing_key_test_rejected': True}, sort_keys=True))
