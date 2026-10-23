"""Populated chat HTTP checks in a marked disposable reference container only."""
import json
import os
from pathlib import Path
import platform
import secrets
import sys
import time
import urllib.error
import urllib.request

CONTEXT = Path('/state/data/chat-history-context.json')


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
        raise RuntimeError('Chat history reference failed: ' + label)


def save_context(context, create=False):
    flags = os.O_WRONLY | os.O_CREAT | (os.O_EXCL if create else os.O_TRUNC)
    with os.fdopen(os.open(CONTEXT, flags, 0o600), 'w') as output:
        json.dump(context, output)


def main():
    if platform.system() != 'Linux' or os.getuid() != 1000 or os.environ.get('ARTEX_DISPOSABLE_REFERENCE') != '1':
        raise RuntimeError('Chat fixture requires an isolated disposable reference container')
    phase = sys.argv[1] if len(sys.argv) == 2 else ''
    require(phase in ('prepare', 'initial', 'final'), 'phase')
    if phase == 'prepare':
        require(not CONTEXT.exists(), 'fresh reference context')
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
        context = {'token': session['token']}
    else:
        context = json.loads(CONTEXT.read_text())

    def api(method, path, body=None):
        status, value = request(method, path, body, context['token'])
        require(status == 200, method + ' ' + path)
        return value

    if phase == 'prepare':
        require(not api('GET', '/api/conversations')['conversations'], 'fresh conversations')
        key = sorted(agent['key'] for agent in api('GET', '/api/agents')['agents'])[0]
        created = api('POST', '/api/conversations', {
            'agent_key': key, 'title': 'Native chat history fixture', 'llm_profile_id': None})
        context.update(identity=created['id'], agent=key)
        save_context(context, create=True)
        return
    route = '/api/conversations/' + str(context['identity'])
    if phase == 'initial':
        latest = api('GET', route + '/messages?limit=200')
        require(len(latest['items']) == 200 and latest['hasMore'] and not latest['running'], 'latest page')
        older = api('GET', route + '/messages?limit=200&before=' + str(latest['items'][0]['seq']))
        require(len(older['items']) == 5 and not older['hasMore'], 'older page')
        by_seq = {item['seq']: item for item in older['items'] + latest['items']}
        initial = [by_seq[seq] for seq in sorted(by_seq)]
        first = initial[0]['seq']
        require([item['seq'] for item in initial] == list(range(first, first + 205)), 'complete initial history')
        require(initial[3]['kind'] == 'future_fixture_kind', 'unknown kind')
        require(all(not item.get('detail') for item in initial), 'lazy details')
        require(all(item.get('tool_use_id') == 'fixture-call' and item.get('tool') == 'fixture-tool'
                    for item in initial[1:3]), 'tool pair')
        require(initial[-1].get('input_tokens') == 100 and initial[-1].get('output_tokens') == 10, 'result usage')
        detail = api('GET', route + '/messages/' + str(first))['detail']
        require(detail == 'guest fixture detail ' * 512, 'full detail')
        overlap = api('GET', route + '/messages?since=' + str(initial[199]['seq']))
        require(overlap['items'] == initial[-5:], 'overlapping delta')
        merged = {item['seq']: item for item in initial + overlap['items']}
        require([merged[seq] for seq in sorted(merged)] == initial, 'deduplicate overlap')
        context.update(cursor=latest['cursor'], first=first, initial=initial, contract={
            'latest_count': len(latest['items']), 'latest_has_more': latest['hasMore'],
            'older_count': len(older['items']), 'older_has_more': older['hasMore'], 'initial_total': len(initial),
            'initial_cursor_offset': latest['cursor'] - first, 'lazy_details_omitted': True,
            'detail_utf8_bytes': len(detail.encode()), 'event_kinds': sorted({item['kind'] for item in initial}),
            'tool_pair_preserved': True, 'result_input_tokens': initial[-1]['input_tokens'],
            'result_output_tokens': initial[-1]['output_tokens'], 'overlap_count': len(overlap['items']),
            'overlap_deduplicated': True})
        save_context(context)
        return
    delta = api('GET', route + '/messages?since=' + str(context['cursor']))
    require(not delta['running'] and len(delta['items']) == 6, 'final idle delta')
    final = context['initial'] + delta['items']
    require([item['seq'] for item in final] == list(range(context['first'], context['first'] + 211)), 'complete final history')
    summaries = [item['summary'] for item in final[-6:]]
    require(summaries == ['fixture event ' + str(n) for n in range(206, 212)], 'final messages')
    other = api('POST', '/api/conversations', {'agent_key': context['agent'], 'title': 'History scope check', 'llm_profile_id': None})
    cross = api('GET', '/api/conversations/' + str(other['id']) + '/messages/' + str(context['first']))['detail']
    require(not cross, 'detail scope')
    api('DELETE', '/api/conversations/' + str(other['id'])); api('DELETE', route)
    require(not api('GET', '/api/conversations')['conversations'], 'cleanup')
    context['contract'].update(final_total=len(final), final_cursor_offset=delta['cursor'] - context['first'],
        final_summaries=summaries, final_running=delta['running'], cross_conversation_detail_empty=not cross, cleanup=True)
    CONTEXT.unlink()
    print(json.dumps(context['contract'], sort_keys=True))


if __name__ == '__main__':
    main()
