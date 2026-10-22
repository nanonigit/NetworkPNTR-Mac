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


if __name__ == '__main__':
    target = Path('/dev/vdb')
    if not stat.S_ISBLK(target.stat().st_mode) or not is_blank(target):
        raise SystemExit(2)
