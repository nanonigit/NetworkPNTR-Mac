"""Finite catalog contract fixture for a fresh isolated reference container."""
import os
import platform
import secrets
import time

from chat_upload_contract_fixture import Client, require

DESCRIPTION = 'Description e\u0301 \ufeff interior 中文 한국어'
GOAL = 'Local contract fixture only'
NOTE = 'fixture {name} e\u0301'
CHECKS = ['initial_empty', 'category_created', 'duplicate_rejected', 'category_renamed',
          'template_created', 'template_cleared', 'template_relinked',
          'category_deleted_link_cleared', 'single_missing_rejected', 'batch_missing_rejected',
          'template_deleted', 'final_empty']


def array(value, key):
    require(isinstance(value, dict) and key in value and
            (value[key] is None or isinstance(value[key], list)), 'catalog envelope')
    return value[key] or []


def matching_template(row, identifier, draft):
    require(isinstance(row, dict) and type(row.get('id')) is int and row['id'] > 0 and
            (identifier is None or row['id'] == identifier), 'template identity')
    require(all(key in row and row[key] == value for key, value in draft.items()), 'template readback')
    return row


def exercise(client):
    require(array(client.api('GET', '/api/tasks'), 'tasks') == [] and
            array(client.api('GET', '/api/task-categories'), 'categories') == [] and
            array(client.api('GET', '/api/task-templates'), 'templates') == [], 'fresh empty catalog')
    category = client.api('POST', '/api/task-categories', {'name': '  T11  e\u0301 日本語  '}, expected=201)
    require(type(category.get('id')) is int and category['id'] > 0 and
            category.get('name') == 'T11 e\u0301 日本語' and category.get('task_count') == 0, 'created category')
    category_id = category['id']
    status, _ = client.request('POST', '/api/task-categories', {'name': 't11 e\u0301 日本語'})
    require(status == 409, 'duplicate category status')
    renamed = client.api('PATCH', f'/api/task-categories/{category_id}', {'name': 'T11 renamed e\u0301 日本語'})
    require(renamed.get('id') == category_id and renamed.get('name') == 'T11 renamed e\u0301 日本語' and
            renamed.get('task_count') == 0, 'renamed category')
    draft = {'name': 'T11 template e\u0301', 'description': DESCRIPTION, 'goal': GOAL,
             'category_id': category_id, 'intercept_rules': [{'enabled': True, 'action': 'block',
             'kind': 'exact_domain', 'pattern': 'example.invalid', 'note': NOTE}]}
    created = matching_template(client.api('POST', '/api/task-templates', draft, expected=201), None, draft)
    template_id = created['id']
    draft = {**draft, 'name': 'T11 updated e\u0301', 'category_id': None, 'intercept_rules': []}
    matching_template(client.api('PATCH', f'/api/task-templates/{template_id}', draft), template_id, draft)
    cleared = array(client.api('GET', '/api/task-templates'), 'templates')
    require(len(cleared) == 1, 'cleared template count')
    matching_template(cleared[0], template_id, draft)
    draft['category_id'] = category_id
    matching_template(client.api('PATCH', f'/api/task-templates/{template_id}', draft), template_id, draft)
    require(client.api('DELETE', f'/api/task-categories/{category_id}').get('deleted') == category_id, 'deleted category')
    detached = array(client.api('GET', '/api/task-templates'), 'templates')
    require(len(detached) == 1, 'detached template count')
    draft['category_id'] = None
    matching_template(detached[0], template_id, draft)
    status, _ = client.request('PATCH', '/api/tasks/9223372036854775806/category', {'category_id': None})
    require(status == 404, 'nonexistent single task')
    ids = ['9223372036854775806', '9223372036854775805']
    missing = client.api('POST', '/api/tasks/category/batch', {'task_ids': ids, 'category_id': None})
    require('category' in missing and missing['category'] is None and isinstance(missing.get('items'), list) and
            [row.get('id') for row in missing['items']] == ids and
            all(row.get('ok') is False for row in missing['items']), 'nonexistent batch tasks')
    require(client.api('DELETE', f'/api/task-templates/{template_id}').get('deleted') == template_id, 'deleted template')
    require(array(client.api('GET', '/api/task-categories'), 'categories') == [] and
            array(client.api('GET', '/api/task-templates'), 'templates') == [] and
            array(client.api('GET', '/api/tasks'), 'tasks') == [], 'final empty catalog')
    return {'checks': CHECKS, 'categoryName': renamed['name'], 'templateDescription': detached[0]['description'],
            'templateGoal': detached[0]['goal'], 'rulePattern': created['intercept_rules'][0]['pattern'],
            'ruleNote': created['intercept_rules'][0]['note']}


def main():
    require(platform.system() == 'Linux' and os.getuid() == 1000 and
            os.environ.get('ARTEX_DISPOSABLE_REFERENCE') == '1', 'disposable catalog reference environment')
    client = Client()
    for _ in range(120):
        try:
            status, value = client.request('GET', '/api/auth/status')
            if status == 200:
                break
        except (OSError, ValueError):
            pass
        time.sleep(.5)
    else:
        raise RuntimeError('Catalog reference readiness failed')
    require(value.get('initialized') is False and value.get('setup_token_required') is True, 'fresh reference authentication')
    denied, _ = client.request('GET', '/api/task-categories')
    require(denied == 401, 'protected catalog')
    session = client.api('POST', '/api/auth/init', {'password': secrets.token_hex(24),
                                                 'setup_token': os.environ['ARTEX_SETUP_TOKEN']})
    client.token = session['token']
    import json
    print(json.dumps(exercise(client), ensure_ascii=False))


if __name__ == '__main__':
    main()
