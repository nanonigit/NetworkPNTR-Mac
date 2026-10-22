"""Trusted fixture; execute through the existing custom-tool test API in a fresh VM only."""
import json
import os
import platform
import subprocess
from urllib.parse import unquote, urlparse

SQL = r"""
BEGIN;
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM tasks) OR EXISTS (SELECT 1 FROM findings)
 OR EXISTS (SELECT 1 FROM assets) OR EXISTS (SELECT 1 FROM conversations)
 OR EXISTS (SELECT 1 FROM llm_usage) OR EXISTS (SELECT 1 FROM intercept_pending)
 OR (SELECT count(*) FROM llm_profiles WHERE name='Fixture OpenAI edited' AND is_default) != 1
 THEN RAISE EXCEPTION 'fresh dashboard fixture required'; END IF;
END $$;
INSERT INTO llm_profiles(name,format,model,is_default) VALUES ('Dashboard secondary','openai','fixture-secondary',false);
INSERT INTO explorations(id,description,goal,status,created_at) VALUES
 (1,'Dashboard fixture A','No execution','achieved','2026-10-21T10:00:00Z'),
 (2,'Dashboard fixture B','No execution','failed','2026-10-20T10:00:00Z');
INSERT INTO tasks(id,description,goal,exploration_id,status,llm_profile_id,created_at) VALUES
 (1,'Dashboard fixture A','No execution',1,'done',NULL,'2026-10-21T10:00:00Z'),
 (2,'Dashboard fixture B','No execution',2,'failed',(SELECT id FROM llm_profiles WHERE name='Dashboard secondary'),'2026-10-20T10:00:00Z');
INSERT INTO activity(exploration_id,worker,kind,tool,summary,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,created_at) VALUES
 (1,'mainagent','result',NULL,'Safe fixture A',100,20,40,5,'2026-10-21T12:00:00Z'),
 (2,'worker','result',NULL,'Safe fixture B',50,10,5,1,'2026-10-20T12:00:00Z'),
 (1,'planner','tool_use','fixture-tool','No command was executed',NULL,NULL,NULL,NULL,'2026-10-22T10:00:00Z');
INSERT INTO findings(task_id,vulnclass,severity,summary,created_at) VALUES
 (1,'fixture-high','high','Safe fixture only','2026-10-21T12:00:00Z'),
 (2,'fixture-low','low','Safe fixture only','2026-10-22T12:00:00Z');
INSERT INTO assets(type,url,method) VALUES
 ('endpoint','https://fixture.invalid/a','GET'),('endpoint','https://fixture.invalid/b','GET');
INSERT INTO assets(type,ip) VALUES ('ip','192.0.2.1');
INSERT INTO conversations(id,agent_key,title,llm_profile_id,created_at) VALUES
 (1,'main','Dashboard fixture conversation',NULL,'2026-10-21T11:00:00Z');
INSERT INTO conversation_activities(conversation_id,kind,summary,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,created_at)
 VALUES (1,'result','Safe fixture conversation',30,5,10,0,'2026-10-21T11:00:00Z');
INSERT INTO llm_usage(ts,task_id,profile_name,input_tokens,output_tokens,cache_read,cache_write,status) VALUES
 ('2026-10-21T12:00:00Z','1','Fixture OpenAI edited',80,10,20,3,'ok'),
 ('2026-10-20T12:00:00Z','2','Dashboard secondary',50,20,5,2,'ok'),
 ('2026-10-22T12:00:00Z','1','removed-name',10,2,1,0,'ok'),
 ('2026-10-01T12:00:00Z','1','Fixture OpenAI edited',999,0,0,0,'ok');
INSERT INTO intercept_pending(agent_name,tool_name,created_at) VALUES
 ('fixture-agent','fixture-tool-1','2026-10-22T09:00:01Z'),
 ('fixture-agent','fixture-tool-2','2026-10-22T09:00:02Z'),
 ('fixture-agent','fixture-tool-3','2026-10-22T09:00:03Z'),
 ('fixture-agent','fixture-tool-4','2026-10-22T09:00:04Z');
SELECT setval('explorations_id_seq',2),setval('tasks_id_seq',2),setval('conversations_id_seq',1);
COMMIT;
"""


def main():
    # Do not permit this script to seed a host database accidentally.
    assert platform.system() == 'Linux' and platform.machine() == 'aarch64' and os.getuid() == 1000
    parsed = urlparse(os.environ['ARTEX_PG_DSN'])
    assert parsed.hostname == '127.0.0.1' and parsed.path == '/artex'
    child_env = dict(os.environ, PGHOST=parsed.hostname, PGPORT=str(parsed.port or 5432),
                     PGDATABASE='artex', PGUSER=unquote(parsed.username or ''),
                     PGPASSWORD=unquote(parsed.password or ''))
    result = subprocess.run(['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1'], input=SQL.encode(),
                            env=child_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
    assert result.returncode == 0, 'Fixture transaction failed'
    print(json.dumps({'fixture_seeded': True, 'linux_guest': True, 'aarch64': True, 'uid': os.getuid()}))


if __name__ == '__main__':
    main()
