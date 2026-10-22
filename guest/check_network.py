"""Reject unexpected guest connectivity before starting the backend."""
from pathlib import Path


def inspect(interfaces=Path('/sys/class/net'), ipv4=Path('/proc/net/route'),
            ipv6=Path('/proc/net/ipv6_route')):
    devices = sorted(path for path in interfaces.iterdir() if path.is_dir())
    if not any(path.name == 'lo' for path in devices):
        raise ValueError('Loopback evidence missing')
    hardware = sum((path / 'device').is_symlink() or (path / 'device').exists() for path in devices)
    active = sum(path.name != 'lo' and bool(int((path / 'flags').read_text().strip(), 16) & 1)
                 for path in devices)
    v4_rows = ipv4.read_text().splitlines()
    if not v4_rows or not v4_rows[0].startswith('Iface'):
        raise ValueError('IPv4 route evidence missing')
    routes = sum(bool(row.split()) and row.split()[0] != 'lo' for row in v4_rows[1:])
    routes += sum(bool(row.split()) and row.split()[-1] != 'lo' for row in ipv6.read_text().splitlines())
    return {'network_interfaces': ','.join(path.name for path in devices),
            'network_hardware_devices': hardware, 'network_nonloopback_up': active,
            'network_external_routes': routes}


def is_isolated(result):
    return all(result[key] == 0 for key in
               ['network_hardware_devices', 'network_nonloopback_up', 'network_external_routes'])


if __name__ == '__main__':
    evidence = inspect()
    for key, value in evidence.items():
        print(f'{key}={value}', flush=True)
    raise SystemExit(0 if is_isolated(evidence) else 1)
