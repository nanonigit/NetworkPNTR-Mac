"""Developer-only fixed archive fault/audit operations, never a file-command interface."""
import hashlib
import json
import os
import re
import stat
import subprocess

from task_archive_seed_guest import DATA_ROOT, NAME, GOAL, validate_environment

AUDIT_KEYS = ('foreign_tasks', 'foreign_archives', 'profiles', 'activity', 'conversations', 'llm_usage', 'llm_records')
AUDIT_SQL = """SELECT json_build_object(
 'foreign_tasks',(SELECT count(*) FROM tasks WHERE id NOT IN (7101,7102)),
 'foreign_archives',(SELECT count(*) FROM task_archives WHERE task_id NOT IN (7101,7102)),
 'profiles',(SELECT count(*) FROM llm_profiles),
 'activity',(SELECT count(*) FROM activity),
 'conversations',(SELECT count(*) FROM conversations),
 'llm_usage',(SELECT count(*) FROM llm_usage),
 'llm_records',(SELECT count(*) FROM llm_records));"""


def query(environment, sql):
    try:
        result = subprocess.run(['psql', '-X', '--no-password', '-Aqt', '-v', 'ON_ERROR_STOP=1', '-c', sql],
                                env=environment, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=15)
        if result.returncode != 0 or len(result.stdout) > 8192:
            raise RuntimeError('Archive fixture query failed')
        value = json.loads(result.stdout)
        if not isinstance(value, dict):
            raise RuntimeError('Archive fixture query shape failed')
        return value
    except (OSError, subprocess.SubprocessError, ValueError):
        raise RuntimeError('Archive fixture query failed') from None


def audit():
    environment = validate_environment()
    counts = query(environment, AUDIT_SQL)
    if any(key not in counts or type(counts[key]) is not int or counts[key] != 0 for key in AUDIT_KEYS):
        raise RuntimeError('Archive fixture activity audit failed')
    return {'fixture_audit': True, 'uid': os.getuid(), 'counts': {key: counts[key] for key in AUDIT_KEYS}}


def package_digest(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or not 0 < before.st_size <= 8 * 1024 * 1024:
            raise RuntimeError('Archive fixture package type/size failed')
        digest = hashlib.sha256()
        total = 0
        while True:
            chunk = stream.read(65536)
            if not chunk:
                break
            total += len(chunk)
            if total > before.st_size:
                raise RuntimeError('Archive fixture package grew')
            digest.update(chunk)
        after = os.fstat(stream.fileno())
        if total != before.st_size or (after.st_ino, after.st_dev, after.st_size, after.st_mtime_ns) != (before.st_ino, before.st_dev, before.st_size, before.st_mtime_ns):
            raise RuntimeError('Archive fixture package changed')
        return digest.hexdigest(), (before.st_dev, before.st_ino)


def set_package_hidden(hidden, identifier, digest):
    environment = validate_environment()
    if type(hidden) is not bool or type(identifier) is not int or not 0 < identifier < 2 ** 63 or not isinstance(digest, str) or re.fullmatch('[0-9a-f]{64}', digest) is None:
        raise RuntimeError('Archive fixture control identity failed')
    # Only a validated integer is formatted; values, paths and SQL identifiers are never caller text.
    row = query(environment, 'SELECT row_to_json(item) FROM (SELECT id,task_id,state,archive_path,sha256,task_name,task_goal FROM task_archives WHERE id=' + str(identifier) + ') item;')
    package = DATA_ROOT / 'archives/tasks' / ('task-7101-' + str(identifier) + '.tar.zst')
    backup = package.with_name(package.name + '.t17-quarantine')
    if (type(row.get('id')) is not int or row['id'] != identifier or type(row.get('task_id')) is not int or row['task_id'] != 7101
            or row.get('task_name') != NAME or row.get('task_goal') != GOAL or row.get('state') != ('ready' if hidden else 'restore_failed')
            or row.get('archive_path') != str(package) or row.get('sha256') != digest):
        raise RuntimeError('Archive fixture package ownership failed')
    try:
        if DATA_ROOT.resolve(strict=True) != DATA_ROOT or package.parent.resolve(strict=True) != package.parent:
            raise RuntimeError('Archive fixture package parent failed')
        source, destination = (package, backup) if hidden else (backup, package)
        if source.is_symlink() or destination.exists() or destination.is_symlink():
            raise RuntimeError('Archive fixture refuses a symlink or overwrite')
        actual, identity = package_digest(source)
        if actual != digest:
            raise RuntimeError('Archive fixture package digest failed')
        os.link(source, destination, follow_symlinks=False)
        linked, original = destination.lstat(), source.lstat()
        if (linked.st_dev, linked.st_ino) != identity or (original.st_dev, original.st_ino) != identity:
            raise RuntimeError('Archive fixture package identity changed')
        source.unlink()
    except OSError:
        raise RuntimeError('Archive fixture package operation failed') from None
    return {'fixture_control': True, 'operation': 'hide' if hidden else 'repair', 'archive_id': identifier,
            'task_id': 7101, 'sha256': digest, 'uid': os.getuid()}


if __name__ == '__main__':
    raise RuntimeError('Use the explicit developer archive probe')
