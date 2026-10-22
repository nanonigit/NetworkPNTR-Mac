#!/usr/bin/env python3
"""Assemble a pinned Linux boot proof without executing guest code on the host."""
from pathlib import Path
import gzip
import hashlib
import io
import json
import stat
import struct
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = {
    "linux-virt": ("6.12.114-r0", "345b2d561443cd8c978cbcc0f36f2374b3ef702debb747221384b4ddc07d6a77"),
    "busybox-static": ("1.37.0-r20", "ee469aee2958feffd7f64dd96655704025ff60af614f77a1d7323dc237c34da2"),
}


def package(name):
    version, expected = PACKAGES[name]
    url = f"https://dl-cdn.alpinelinux.org/alpine/v3.22/main/aarch64/{name}-{version}.apk"
    cache = ROOT / ".build-cache/downloads"
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / f"{name}-{version}.apk"
    if not path.exists():
        temporary = path.with_suffix(".partial")
        try:
            with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as target:
                size = 0
                while chunk := response.read(1024 * 1024):
                    size += len(chunk)
                    if size > 128 * 1024 * 1024:
                        raise ValueError("Package download exceeds size limit")
                    target.write(chunk)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError(f"Checksum mismatch: {path.name}")
    return path, url


def member(apk, name):
    # Read selected regular members only. Never extract archive paths to the host.
    with tarfile.open(apk, "r:gz", ignore_zeros=True) as archive:
        info = archive.getmember(name)
        if not info.isfile() or info.size > 128 * 1024 * 1024:
            raise ValueError("Unexpected package member")
        return archive.extractfile(info).read()


def entry(name, mode, data=b"", inode=1, rdevmajor=0, rdevminor=0):
    filename = name.encode() + b"\0"
    fields = [inode, mode, 0, 0, 1, 0, len(data), 0, 0, rdevmajor, rdevminor, len(filename), 0]
    header = b"070701" + b"".join(f"{n:08x}".encode() for n in fields)
    block = header + filename
    block += b"\0" * (-len(block) % 4)
    return block + data + b"\0" * (-len(data) % 4)


def unpack_kernel(kernel):
    # Alpine ARM64 uses the Linux EFI zboot wrapper; VZ requires the inner Image.
    if kernel[4:8] == b"zimg" and kernel[24:28] == b"gzip":
        offset, size = struct.unpack_from("<II", kernel, 8)
        if offset + size > len(kernel):
            raise ValueError("Invalid EFI zboot payload")
        with gzip.GzipFile(fileobj=io.BytesIO(kernel[offset:offset + size])) as compressed:
            kernel = compressed.read(128 * 1024 * 1024 + 1)
        if len(kernel) > 128 * 1024 * 1024:
            raise ValueError("Kernel exceeds size limit")
    if kernel[56:60] != b"ARM\x64":
        raise ValueError("Expected uncompressed ARM64 Linux Image")
    return kernel


def main():
    linux, linux_url = package("linux-virt")
    busybox, busybox_url = package("busybox-static")
    kernel = unpack_kernel(member(linux, "boot/vmlinuz-virt"))
    archive = b""
    for index, name in enumerate([".", "bin", "dev", "proc", "sys", "tmp"]):
        archive += entry(name, stat.S_IFDIR | 0o755, inode=index + 1)
    archive += entry("dev/console", stat.S_IFCHR | 0o600, inode=10, rdevmajor=5, rdevminor=1)
    archive += entry("bin/busybox", stat.S_IFREG | 0o755, member(busybox, "bin/busybox.static"), inode=11)
    archive += entry("bin/sh", stat.S_IFLNK | 0o777, b"busybox", inode=12)
    archive += entry("init", stat.S_IFREG | 0o755, (ROOT / "guest/init").read_bytes(), inode=13)
    archive += entry("TRAILER!!!", 0, inode=14)
    initramfs = gzip.compress(archive, mtime=0)
    output = ROOT / "guest/artifacts"
    output.mkdir(parents=True, exist_ok=True)
    (output / "Image").write_bytes(kernel)
    (output / "initramfs.cpio.gz").write_bytes(initramfs)
    manifest = {
        "architecture": "arm64", "kernel": "Image", "kernelSHA256": hashlib.sha256(kernel).hexdigest(),
        "initramfs": "initramfs.cpio.gz", "initramfsSHA256": hashlib.sha256(initramfs).hexdigest(),
        "packages": {name: {"version": value[0], "sha256": value[1]} for name, value in PACKAGES.items()},
        "sources": [linux_url, busybox_url], "networkDevices": 0, "hostShares": 0,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Guest proof artifacts prepared and checksummed; no guest executable ran on macOS.")


if __name__ == "__main__":
    main()
