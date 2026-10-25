"""Best-effort cleanup of explicitly recorded, owned Docker reference identities."""
import re
import subprocess


def cleanup_reference(docker, containers, network, directory, *, run=subprocess.run):
    identities = list(containers) + ([network] if network else [])
    if not all(isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) for value in identities):
        return {'cleanup': False, 'logs_complete': False, 'errors': ['invalid_owned_inventory']}
    result = {'cleanup': True, 'logs_complete': True, 'errors': []}
    for identity in reversed(containers):
        try:
            logs = run(docker + ['logs', '--tail', '2000', identity], capture_output=True, timeout=20)
            (directory / ('reference-' + identity[:12] + '.log')).write_bytes((logs.stdout or b'') + (logs.stderr or b''))
            if logs.returncode != 0:
                raise RuntimeError('log result unavailable')
        except Exception:
            result['logs_complete'] = False
            result['errors'].append('container_logs_unavailable')
    for identity in reversed(containers):
        try:
            removed = run(docker + ['rm', '--force', identity], capture_output=True, timeout=30)
            if removed.returncode != 0:
                raise RuntimeError('removal unconfirmed')
        except Exception:
            result['cleanup'] = False
            result['errors'].append('container_remove_unconfirmed')
    if network:
        try:
            removed = run(docker + ['network', 'rm', network], capture_output=True, timeout=30)
            if removed.returncode != 0:
                raise RuntimeError('removal unconfirmed')
        except Exception:
            result['cleanup'] = False
            result['errors'].append('network_remove_unconfirmed')
    return result
