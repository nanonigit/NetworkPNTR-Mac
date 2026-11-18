"""Fixed terminal task data for a fresh no-model diagnostic VM only."""
import json
import os
import platform
import re
import subprocess
from urllib.parse import parse_qsl, unquote, urlsplit

SQL = r"""
BEGIN;
LOCK TABLE tasks, explorations, activity, llm_profiles, llm_usage, findings, conversations IN EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM tasks) OR EXISTS (SELECT 1 FROM explorations)
 OR EXISTS (SELECT 1 FROM activity) OR EXISTS (SELECT 1 FROM llm_profiles)
 OR EXISTS (SELECT 1 FROM llm_usage) OR EXISTS (SELECT 1 FROM findings)
 OR EXISTS (SELECT 1 FROM conversations)
 THEN RAISE EXCEPTION 'fresh no-model MCP task fixture required'; END IF;
END; $$;
INSERT INTO explorations(id,description,goal,status) VALUES
 (7201,'MCP allowed terminal task','Synthetic metadata only; no execution','achieved'),
 (7202,'MCP denied terminal task','Synthetic metadata only; no execution','failed');
INSERT INTO tasks(id,name,description,goal,exploration_id,status,paused,queued,llm_profile_id,active_llm_profile_id,timeout_seconds,plan_heartbeat_seconds,completed_at) VALUES
 (7201,'MCP selected / 許可対象','MCP allowed terminal task','No execution',7201,'done',false,false,NULL,NULL,0,0,'2026-10-22T12:00:00Z'),
 (7202,'MCP unselected / 許可対象外','MCP denied terminal task','No execution',7202,'failed',false,false,NULL,NULL,0,0,'2026-10-22T12:00:00Z');
INSERT INTO activity(id,exploration_id,worker,kind,summary,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens) VALUES
 (7201,7201,'mainagent','result','Synthetic historical counter A',2147483647,6,0,0),
 (7202,7201,'mainagent','result','Synthetic historical counter B',2147483647,7,0,0),
 (7203,7202,'mainagent','result','Synthetic historical counter',17,5,0,0);
ALTER SEQUENCE activity_id_seq RESTART WITH 7204;
ALTER SEQUENCE explorations_id_seq RESTART WITH 7203;
ALTER SEQUENCE tasks_id_seq RESTART WITH 7203;
COMMIT;
"""


def validate_environment():
    if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.getuid() != 1000:
        raise RuntimeError('MCP task fixture requires isolated Linux/aarch64/UID1000')
    if os.environ.get('NETWORKPNTR_MCP_TASK_FIXTURE') != '1':
        raise RuntimeError('MCP task fixture requires explicit diagnostic mode')
    try:
        parsed = urlsplit(os.environ.get('ARTEX_PG_DSN', ''))
        password = unquote(parsed.password or '')
        valid = (parsed.scheme in ('postgres', 'postgresql') and parsed.hostname == '127.0.0.1'
                 and parsed.port == 5432 and unquote(parsed.username or '') == 'artex'
                 and parsed.path == '/artex' and not parsed.fragment
                 and parse_qsl(parsed.query, keep_blank_values=True) == [('sslmode', 'disable')]
                 and re.fullmatch('[0-9a-f]{64}', password) is not None)
    except ValueError:
        valid = False
    if not valid:
        raise RuntimeError('MCP task fixture requires the exact guest loopback database')
    return {'PATH': '/usr/libexec/postgresql16:/usr/bin:/bin', 'PGHOST': '127.0.0.1',
            'PGPORT': '5432', 'PGDATABASE': 'artex', 'PGUSER': 'artex', 'PGPASSWORD': password,
            'PGCONNECT_TIMEOUT': '2', 'PGCLIENTENCODING': 'UTF8'}


def main():
    environment = validate_environment()
    try:
        result = subprocess.run(['/usr/libexec/postgresql16/psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1'],
                                input=SQL.encode(), env=environment, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=15)
    except (OSError, subprocess.SubprocessError):
        raise RuntimeError('MCP task fixture transaction failed') from None
    if result.returncode != 0:
        raise RuntimeError('MCP task fixture transaction failed')
    print(json.dumps({'mcp_task_fixture_seeded': True, 'linux_guest': True, 'uid': os.getuid(), 'task_ids': ['7201', '7202']}))


if __name__ == '__main__':
    main()
