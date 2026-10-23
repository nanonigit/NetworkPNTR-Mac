"""Fixed SQL fixture; main executes only inside the private ARM64 Linux guest."""
import json
import os
import platform
import subprocess
from urllib.parse import unquote, urlparse

SQL = r"""
BEGIN;
LOCK TABLE conversations, conversation_activities IN EXCLUSIVE MODE;
DO $$ BEGIN
 IF (SELECT count(*) FROM conversations) != 1
 OR NOT EXISTS (SELECT 1 FROM conversations WHERE title='Native chat history fixture')
 OR EXISTS (SELECT 1 FROM conversation_activities)
 OR EXISTS (SELECT 1 FROM tasks) OR EXISTS (SELECT 1 FROM findings) OR EXISTS (SELECT 1 FROM assets)
 THEN RAISE EXCEPTION 'fresh chat history fixture required'; END IF;
END $$;
INSERT INTO conversation_activities(conversation_id,worker,kind,tool,tool_use_id,is_error,summary,detail,
 input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,created_at)
SELECT c.id,'fixture',
 CASE n WHEN 1 THEN 'user' WHEN 2 THEN 'tool_use' WHEN 3 THEN 'tool_result'
 WHEN 4 THEN 'future_fixture_kind' WHEN 5 THEN 'usage' WHEN 205 THEN 'result' ELSE 'text' END,
 CASE WHEN n IN (2,3) THEN 'fixture-tool' END,
 CASE WHEN n IN (2,3) THEN 'fixture-call' END,
 false,'fixture event ' || n,
 CASE WHEN n=1 THEN repeat('guest fixture detail ',512) ELSE 'detail ' || n END,
 CASE WHEN n=205 THEN 100 ELSE 0 END,CASE WHEN n=205 THEN 10 ELSE 0 END,0,0,
 '2026-10-23T00:00:00Z'::timestamptz + n * interval '1 second'
FROM conversations c CROSS JOIN generate_series(1,205) AS n ORDER BY n;
COMMIT;
"""
APPEND_SQL = r"""
BEGIN;
LOCK TABLE conversations, conversation_activities IN EXCLUSIVE MODE;
DO $$ BEGIN
 IF (SELECT count(*) FROM conversations) != 1
 OR NOT EXISTS (SELECT 1 FROM conversations WHERE title='Native chat history fixture')
 OR (SELECT count(*) FROM conversation_activities) != 205
 OR (SELECT count(*) FROM conversation_activities WHERE worker='fixture' AND summary LIKE 'fixture event %') != 205
 OR EXISTS (SELECT 1 FROM tasks) OR EXISTS (SELECT 1 FROM findings) OR EXISTS (SELECT 1 FROM assets)
 THEN RAISE EXCEPTION 'initial chat history fixture required'; END IF;
END $$;
INSERT INTO conversation_activities(conversation_id,worker,kind,summary,created_at)
SELECT c.id,'fixture',CASE WHEN n=211 THEN 'result' ELSE 'text' END,'fixture event ' || n,
 '2026-10-23T00:00:00Z'::timestamptz + n * interval '1 second'
FROM conversations c CROSS JOIN generate_series(206,211) AS n ORDER BY n;
COMMIT;
"""


def main(phase='initial'):
    if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.getuid() != 1000:
        raise RuntimeError('Chat fixture requires an isolated Linux guest')
    parsed = urlparse(os.environ.get('ARTEX_PG_DSN', ''))
    if parsed.scheme not in ('postgres', 'postgresql') or parsed.hostname != '127.0.0.1' or parsed.path != '/artex' or parsed.port not in (None, 5432):
        raise RuntimeError('Chat fixture requires the guest loopback artex database')
    if phase not in ('initial', 'append'):
        raise RuntimeError('Unknown chat fixture phase')
    child_env = dict({key: value for key, value in os.environ.items() if not key.startswith('PG')}, PGHOST='127.0.0.1', PGPORT='5432', PGDATABASE='artex',
                     PGUSER=unquote(parsed.username or ''), PGPASSWORD=unquote(parsed.password or ''))
    result = subprocess.run(['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1'],
                            input=(SQL if phase == 'initial' else APPEND_SQL).encode(), env=child_env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
    if result.returncode != 0:
        raise RuntimeError('Chat fixture transaction failed')
    print(json.dumps({'chat_history_seeded': phase, 'linux_guest': True, 'aarch64': True, 'uid': 1000}))


if __name__ == '__main__':
    main()
