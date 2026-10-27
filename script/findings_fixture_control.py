"""Developer-only read audit for the fixed findings fixture; never a SQL or file-command interface."""
import json
import os
import subprocess

from findings_seed_guest import validate_environment

# Every fragment is trusted source text. No caller-provided SQL, ID, filename or host is accepted.
ZERO_QUERIES = {
    'foreign_tasks': 'SELECT count(*) FROM tasks WHERE id NOT BETWEEN 8101 AND 8111',
    'unsafe_tasks': "SELECT count(*) FROM tasks WHERE status <> 'done' OR paused OR queued OR llm_profile_id IS NOT NULL OR active_llm_profile_id IS NOT NULL OR timeout_seconds <> 0 OR plan_heartbeat_seconds <> 0 OR exploration_id <> id OR deleted_at IS NOT NULL OR archived_at IS NOT NULL",
    'foreign_explorations': "SELECT count(*) FROM explorations WHERE id NOT BETWEEN 8101 AND 8111 OR status <> 'achieved'",
    'foreign_nodes': "SELECT count(*) FROM exploration_nodes WHERE exploration_id NOT BETWEEN 8101 AND 8111 OR kind NOT IN ('finding','begin','goal')",
    'foreign_finding_nodes': "SELECT count(*) FROM exploration_nodes WHERE kind='finding' AND NOT ((id BETWEEN 15101 AND 15121 AND exploration_id=8101) OR (id BETWEEN 15122 AND 15131 AND exploration_id=id-15122+8102) OR (id=15190 AND exploration_id=8111))",
    'foreign_findings': 'SELECT count(*) FROM findings WHERE id NOT BETWEEN 9101 AND 9133 OR task_id IS DISTINCT FROM CASE WHEN id<=9121 THEN 8101 WHEN id<=9131 THEN id-9122+8102 ELSE NULL END OR node_id IS DISTINCT FROM CASE WHEN id<=9131 THEN id+6000 ELSE NULL END',
    'foreign_relations': 'SELECT count(*) FROM task_relations WHERE task_id<>8111 OR source_task_id<>8101',
    'foreign_companies': 'SELECT count(*) FROM companies WHERE id<>8200',
    'foreign_assets': "SELECT count(*) FROM assets WHERE id NOT IN (8201,8202,8203) OR company_id IS DISTINCT FROM 8200 OR type IS DISTINCT FROM CASE id WHEN 8201 THEN 'root_domain' WHEN 8202 THEN 'subdomain' WHEN 8203 THEN 'ip' ELSE NULL END",
    'foreign_links': "SELECT count(*) FROM task_asset_links WHERE task_id NOT BETWEEN 8101 AND 8111 OR asset_id NOT IN (8201,8202,8203) OR source<>'system' OR source_node_id IS NOT NULL",
    'foreign_events': "SELECT count(*) FROM notification_events WHERE finding_id<>9101 OR kind<>'finding_status_changed'",
    'profiles': 'SELECT count(*) FROM llm_profiles',
    'task_profiles': 'SELECT count(*) FROM task_llm_profiles',
    'activity': 'SELECT count(*) FROM activity',
    'conversations': 'SELECT count(*) FROM conversations',
    'llm_usage': 'SELECT count(*) FROM llm_usage',
    'llm_records': 'SELECT count(*) FROM llm_records',
    'archives': 'SELECT count(*) FROM task_archives',
    'intercepts': 'SELECT count(*) FROM intercept_pending',
    'retests': 'SELECT count(*) FROM finding_retests',
    'traffic_bindings': 'SELECT count(*) FROM finding_traffic_bindings',
    'traffic_snapshots': 'SELECT count(*) FROM traffic_evidence_snapshots',
    'notification_channels': 'SELECT count(*) FROM notification_channels',
    'notification_deliveries': 'SELECT count(*) FROM notification_deliveries',
}
ZERO_KEYS = tuple(ZERO_QUERIES)
COUNT_QUERIES = {
    'tasks': 'SELECT count(*) FROM tasks', 'explorations': 'SELECT count(*) FROM explorations',
    'relations': 'SELECT count(*) FROM task_relations', 'companies': 'SELECT count(*) FROM companies',
    'assets': 'SELECT count(*) FROM assets', 'findings': 'SELECT count(*) FROM findings',
    'finding_nodes': "SELECT count(*) FROM exploration_nodes WHERE kind='finding'",
    'events': 'SELECT count(*) FROM notification_events',
}
AUDIT_SQL = "SET statement_timeout = '5s'; SELECT json_build_object(" + ','.join(
    "'" + key + "',(" + sql + ')' for key, sql in list(ZERO_QUERIES.items()) + list(COUNT_QUERIES.items())
) + ');'


def _query(environment):
    try:
        result = subprocess.run(['psql', '-X', '--no-password', '-Aqt', '-v', 'ON_ERROR_STOP=1', '-c', AUDIT_SQL],
                                env=environment, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=15)
        if result.returncode != 0 or len(result.stdout) > 8192:
            raise RuntimeError('Findings fixture audit query failed')
        value = json.loads(result.stdout)
        if not isinstance(value, dict):
            raise RuntimeError('Findings fixture audit query shape failed')
        return value
    except (OSError, subprocess.SubprocessError, ValueError):
        raise RuntimeError('Findings fixture audit query failed') from None


def audit(*, fresh=False):
    environment = validate_environment()
    if type(fresh) is not bool:
        raise RuntimeError('Findings fixture audit phase failed')
    counts = _query(environment)
    keys = set(ZERO_KEYS) | set(COUNT_QUERIES)
    if (set(counts) != keys or any(type(counts[key]) is not int or counts[key] < 0 for key in keys)
            or any(counts[key] != 0 for key in ZERO_KEYS)):
        raise RuntimeError('Findings fixture activity audit failed')
    owned = (counts['tasks'], counts['explorations'], counts['relations'], counts['companies'], counts['assets'])
    dataset = (counts['findings'], counts['finding_nodes'])
    if fresh:
        valid = owned == (0, 0, 0, 0, 0) and dataset == (0, 0) and counts['events'] == 0
    else:
        # Startup may add begin/goal nodes. Internal status events do not imply configured external delivery.
        valid = owned == (11, 11, 1, 1, 3) and dataset in ((33, 32), (31, 31)) and counts['events'] <= 3
    if not valid:
        raise RuntimeError('Findings fixture owned state audit failed')
    return {'fixture_audit': True, 'uid': os.getuid(), 'fresh': fresh, 'counts': counts}
