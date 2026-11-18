#!/usr/bin/env python3
"""Compare production TLS logic in two process contexts using one fixed public GET.

Developer diagnosis only. It neither changes network permissions nor provides an
application transport fallback. No credentials, inference or response bodies.
"""
import argparse
import ctypes
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
HOST = 'api.openai.com'
HEADER = b'GET /v1/models HTTP/1.1\r\nHost: api.openai.com\r\nConnection: close\r\n\r\n'


def require_public_ipv4(value):
    address = ipaddress.ip_address(value)
    if address.version != 4 or not address.is_global:
        raise ValueError('Only a resolved public IPv4 address is admitted')
    return str(address)


def classify_pair(standalone, python):
    reached = lambda item: item.get('result') == 0 and item.get('httpStatus') == 401
    if reached(standalone) and reached(python):
        return 'both-reached-upstream'
    if standalone.get('result') != 0 and reached(python):
        return 'process-context-difference'
    return 'unresolved'


CLIENT = r'''
#include "NetworkPNTRCloudTLS.h"
#include <stdio.h>
#include <string.h>
struct state { char prefix[13]; size_t size; int status; };
static int cancelled(void *p) { (void)p; return 0; }
static int receive(void *p, const uint8_t *bytes, size_t count) {
    struct state *s=p;
    size_t take=12-s->size; if(count<take) take=count;
    memcpy(s->prefix+s->size,bytes,take); s->size+=take;
    if(s->size<12) return 0;
    if(memcmp(s->prefix,"HTTP/1.",7)==0) (void)sscanf(s->prefix,"HTTP/1.%*c %d",&s->status);
    return 2;
}
int main(int argc,char **argv) {
    if(argc!=2) return 64;
    artx_cloud_options options={.hostname="api.openai.com",.numeric_ip=argv[1],.port=443,
        .connect_timeout_ms=4000,.total_timeout_ms=8000,.maximum_response_bytes=4096};
    const char *header="GET /v1/models HTTP/1.1\r\nHost: api.openai.com\r\nConnection: close\r\n\r\n";
    struct state s={0};
    artx_cloud_result result=artx_cloud_tls_exchange(&options,(const uint8_t*)header,strlen(header),NULL,0,cancelled,receive,&s);
    printf("{\"result\":%d,\"httpStatus\":%d}\n",result,s.status);
    return result;
}
'''


class Options(ctypes.Structure):
    _fields_ = [('hostname', ctypes.c_char_p), ('numeric_ip', ctypes.c_char_p), ('port', ctypes.c_uint16),
                ('connect_timeout_ms', ctypes.c_uint32), ('total_timeout_ms', ctypes.c_uint32),
                ('maximum_response_bytes', ctypes.c_size_t)]


def python_exchange(library, address):
    cancel_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)
    receive_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t)
    loaded = ctypes.CDLL(str(library.resolve()))
    exchange = loaded.artx_cloud_tls_exchange
    exchange.argtypes = [ctypes.POINTER(Options), ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t,
                         cancel_type, receive_type, ctypes.c_void_p]
    exchange.restype = ctypes.c_int
    prefix = bytearray()
    status = 0

    @cancel_type
    def cancelled(_):
        return 0

    @receive_type
    def receive(_, data, count):
        nonlocal status
        prefix.extend(ctypes.string_at(data, min(count, 12 - len(prefix))))
        if len(prefix) < 12:
            return 0
        if prefix.startswith(b'HTTP/1.') and prefix[9:12].isdigit():
            status = int(prefix[9:12])
        return 2

    address = require_public_ipv4(address)
    options = Options(HOST.encode(), address.encode(), 443, 4000, 8000, 4096)
    start = time.monotonic()
    result = exchange(ctypes.byref(options), HEADER, len(HEADER), None, 0, cancelled, receive, None)
    return {'result': result, 'httpStatus': status, 'seconds': round(time.monotonic() - start, 3)}



def resolve_public_ipv4(environment):
    resolver = subprocess.run([sys.executable, '-I', '-c',
        'import json,socket;print(json.dumps(sorted({r[4][0] for r in socket.getaddrinfo("api.openai.com",443,socket.AF_INET,socket.SOCK_STREAM)})))'],
        capture_output=True, check=True, timeout=8, env=environment)
    if len(resolver.stdout) > 4096:
        raise ValueError('Unexpected resolver output size')
    addresses = {require_public_ipv4(value) for value in json.loads(resolver.stdout)}
    if not addresses:
        raise ValueError('No admitted vendor address')
    return sorted(addresses)[0]


def probe(output):
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('This diagnosis requires an Apple Silicon Mac')
    output.mkdir(mode=0o700)
    # Do not forward unrelated credentials or loader/compiler injection settings.
    environment = {key: os.environ[key] for key in ('PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'DEVELOPER_DIR', 'SDKROOT') if key in os.environ}
    address = resolve_public_ipv4(environment)
    paths = [ROOT / 'Sources/NetworkPNTRCloudTLS/NetworkPNTRCloudTLS.c',
             ROOT / 'Sources/NetworkPNTRCloudTLS/include/NetworkPNTRCloudTLS.h']
    frozen = {}
    for source in paths:
        if source.is_symlink() or not source.is_file() or source.stat().st_size > 128 * 1024:
            raise ValueError('Expected bounded regular transport source')
        target = output / source.name
        shutil.copyfile(source, target)
        frozen[source.name] = hashlib.sha256(target.read_bytes()).hexdigest()
    (output / 'client.c').write_text(CLIENT)
    flags = ['/usr/bin/xcrun', 'clang', '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations', '-I', str(output),
             str(output / 'NetworkPNTRCloudTLS.c')]
    frameworks = ['-framework', 'Security', '-framework', 'CoreFoundation']
    executable, library = output / 'client', output / 'libcloudtls.dylib'
    subprocess.run([*flags, str(output / 'client.c'), *frameworks, '-o', str(executable)], env=environment, check=True, timeout=60, capture_output=True)
    subprocess.run([*flags, '-dynamiclib', *frameworks, '-o', str(library)], env=environment, check=True, timeout=60, capture_output=True)
    start = time.monotonic()
    process = subprocess.run([str(executable), address], env=environment, capture_output=True, timeout=12)
    if len(process.stdout) > 1024:
        raise ValueError('Unexpected probe output size')
    standalone = json.loads(process.stdout)
    if set(standalone) != {'result', 'httpStatus'} or process.returncode != standalone['result']:
        raise ValueError('Unexpected standalone probe result')
    standalone['seconds'] = round(time.monotonic() - start, 3)
    driver = output / 'probe_driver.py'
    shutil.copyfile(Path(__file__), driver)
    child_code = 'import json,runpy,sys;from pathlib import Path;m=runpy.run_path(sys.argv[1],run_name="networkpntr_context_probe");print(json.dumps(m["python_exchange"](Path(sys.argv[2]),sys.argv[3])))'
    child = subprocess.run([sys.executable, '-I', '-c', child_code, str(driver), str(library), address],
                           env=environment, capture_output=True, check=True, timeout=12)
    if len(child.stdout) > 1024:
        raise ValueError('Unexpected Python probe output size')
    python = json.loads(child.stdout)
    if set(python) != {'result', 'httpStatus', 'seconds'}:
        raise ValueError('Unexpected Python probe schema')
    result = {'scope': 'developer fixed vendor GET, no key or inference; not an application fallback',
              'host': HOST, 'publicIPv4': address, 'frozenSourceSHA256': frozen,
              'diagnosticSourceSHA256': hashlib.sha256(driver.read_bytes()).hexdigest(),
              'standaloneExecutableSHA256': hashlib.sha256(executable.read_bytes()).hexdigest(),
              'sharedLibrarySHA256': hashlib.sha256(library.read_bytes()).hexdigest(),
              'standalone': standalone, 'python': python,
              'observation': classify_pair(standalone, python), 'rootCause': 'not-established',
              'applicationNetworkAcceptance': False}
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New private diagnostic directory')
    args = parser.parse_args()
    print(json.dumps(probe(args.output.resolve()), indent=2))
