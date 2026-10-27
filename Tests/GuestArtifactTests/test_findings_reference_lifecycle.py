"""Mocked process-lifecycle checks only; actual reference acceptance requires a real container."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'script'))
SPEC = importlib.util.spec_from_file_location('findings_reference', ROOT / 'script/findings_reference.py')
reference = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(reference)


class Process:
    def __init__(self, waits=None):
        self.waits = list(waits or [0]); self.timeouts = []; self.terminated = 0; self.killed = 0
    def poll(self): return None
    def terminate(self): self.terminated += 1
    def kill(self): self.killed += 1
    def wait(self, timeout):
        self.timeouts.append(timeout); value = self.waits.pop(0)
        if isinstance(value, Exception): raise value
        return value


class ReferenceLifecycleTests(unittest.TestCase):
    def environment(self, root, processes, *, unreachable=False):
        stack = contextlib.ExitStack(); starts = []; auth = []
        class Client:
            token = None
            def request(self, method, path, body=None):
                if unreachable: raise OSError('fixture not ready')
                if path == '/api/auth/status': return 200, dict(initialized=len(starts) > 1, setup_token_required=True)
                return 401, {}
            def api(self, method, path, body=None):
                auth.append((method, path, self.token))
                return {'token': 'fixture-session-token'} if method == 'POST' else []
        def start(*args, **kwargs):
            starts.append((args, kwargs)); return processes[len(starts)-1]
        stack.enter_context(patch.object(reference.platform, 'system', return_value='Linux'))
        stack.enter_context(patch.object(reference.platform, 'machine', return_value='aarch64'))
        stack.enter_context(patch.object(reference.os, 'getuid', return_value=1000))
        stack.enter_context(patch.dict(reference.os.environ, {'ARTEX_DISPOSABLE_REFERENCE': '1'}, clear=True))
        stack.enter_context(patch.object(reference, 'inspect_network', return_value=dict(network_interfaces='lo',network_hardware_devices=0,network_nonloopback_up=0,network_external_routes=0)))
        stack.enter_context(patch.object(reference, 'DATA_ROOT', root))
        stack.enter_context(patch.object(reference.seed, 'validate_environment', return_value={'PGPASSWORD': 'fixture-pg-password'}))
        stack.enter_context(patch.object(reference.control, 'audit', return_value={'fixture_audit': True}))
        stack.enter_context(patch.object(reference.seed, 'main'))
        stack.enter_context(patch.object(reference, 'Client', Client))
        stack.enter_context(patch.object(reference.subprocess, 'Popen', side_effect=start))
        stack.enter_context(patch.object(reference.time, 'sleep'))
        stack.enter_context(patch.object(reference, 'sha256_file', return_value='a' * 64))
        return stack, starts, auth

    def test_readiness_exhaustion_stops_owned_process_without_another_start(self):
        process = Process()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'data'; root.mkdir()
            stack, starts, _ = self.environment(root, [process], unreachable=True)
            with stack, self.assertRaises(RuntimeError): reference.main()
            self.assertEqual(len(starts), 1); self.assertEqual(process.terminated, 1)
            self.assertEqual(process.timeouts, [10]); self.assertEqual(process.killed, 0)

    def test_stop_timeout_escalates_only_owned_process_and_never_returns_success(self):
        process = Process([subprocess.TimeoutExpired('fixture', 20), subprocess.TimeoutExpired('fixture', 10), 0])
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'data'; root.mkdir()
            stack, starts, _ = self.environment(root, [process])
            with stack, self.assertRaises(subprocess.TimeoutExpired): reference.main()
            self.assertEqual(len(starts), 1); self.assertEqual(process.terminated, 2)
            self.assertEqual(process.killed, 1); self.assertEqual(process.timeouts, [20, 10, 5])

    def test_three_starts_keep_session_without_login_fallback_and_stop_each_process(self):
        processes = [Process(), Process(), Process()]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'data'; root.mkdir()
            stack, starts, auth = self.environment(root, processes)
            bounded = SimpleNamespace(calls=100, audits=[], audit=lambda: None)
            stack.enter_context(patch.object(reference, 'Bounded', return_value=bounded))
            stack.enter_context(patch.object(reference, 'before_restart', return_value=dict(initialChecks=[], mutationChecks=[], partialHTTPStatus=500, beforeRequestCount=116)))
            stack.enter_context(patch.object(reference, 'read_snapshot', return_value=[]))
            output = io.StringIO()
            with stack, contextlib.redirect_stdout(output): reference.main()
            result = json.loads(output.getvalue())
            self.assertEqual(result['backend_starts'], 3); self.assertEqual(result['cooperative_stops'], 3)
            self.assertEqual(len(starts), 3)
            self.assertEqual([p.terminated for p in processes], [1, 1, 1])
            self.assertEqual([call[1] for call in auth if call[0] == 'POST'], ['/api/auth/init'])
            self.assertEqual([call[2] for call in auth if call[0] == 'GET'], ['fixture-session-token'] * 2)
            for args, kwargs in starts:
                self.assertEqual(args[0][0], '/opt/artex/artex'); self.assertEqual(args[0][-2:], ['-proxy', ''])
                self.assertEqual(kwargs['cwd'], root)

    def test_hash_stream_is_bounded_and_exact(self):
        import hashlib
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixed'; path.write_bytes(b'fixture-bytes')
            self.assertEqual(reference.sha256_file(path), hashlib.sha256(b'fixture-bytes').hexdigest())
            with self.assertRaises(RuntimeError): reference.sha256_file(path, maximum=2)


if __name__ == '__main__': unittest.main()
