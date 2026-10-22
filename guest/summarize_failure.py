"""Emit only fixed diagnostic categories, never raw backend log text."""
from pathlib import Path


def categories(content):
    patterns = {'go_panic': ('panic:',), 'go_runtime_fatal': ('fatal error:',),
                'signal_fault': ('SIGSEGV', 'SIGBUS', 'SIGILL', 'segmentation fault'),
                'database_open': ('open stores:',), 'jwt_key': ('[auth] JWT key:',),
                'http_serve': ('serve:',), 'connection_refused': ('connection refused',),
                'database_auth': ('password authentication failed',),
                'database_recovery': ('database system is starting up', 'database system is in recovery mode')}
    return [name for name, needles in patterns.items() if any(needle in content for needle in needles)]


if __name__ == '__main__':
    path = Path('/run/artex.log')
    # Inspect a bounded tail. The raw file stays private and is never sent to serial.
    with path.open('rb') as file:
        file.seek(0, 2)
        file.seek(max(0, file.tell() - 65536))
        found = categories(file.read().decode('utf-8', errors='replace'))
    print('backend_failure_categories=' + (','.join(found) if found else 'unclassified'), flush=True)
