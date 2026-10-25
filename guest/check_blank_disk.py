#!/usr/bin/python3
"""Recognize only an entirely blank disk, using a constant amount of memory."""
from pathlib import Path
import stat


def is_blank(path):
    with path.open('rb', buffering=0) as disk:
        while chunk := disk.read(1024 * 1024):
            if chunk.strip(b'\0'):
                return False
    return True


def check_status(path):
    """Return 2 only for observed data; invalid devices and I/O are execution failures."""
    try:
        if not stat.S_ISBLK(path.stat().st_mode):
            return 3
        return 0 if is_blank(path) else 2
    except (OSError, ValueError):
        return 3


if __name__ == '__main__':
    raise SystemExit(check_status(Path('/dev/vdb')))
