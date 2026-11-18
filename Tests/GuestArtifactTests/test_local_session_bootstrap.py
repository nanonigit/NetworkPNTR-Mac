import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch
import json

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'script'))
from local_session_bootstrap import NEW, patch_init
from build_local_session import remove_owned_parent_alias, refresh_composite_metadata


class LocalSessionBootstrapTests(unittest.TestCase):
    def test_overlay_preserves_unrelated_variant_content(self):
        source = (Path(__file__).resolve().parents[2] / 'guest/backend-init').read_bytes()
        patched = patch_init(source + b'\n# cloud runtime sentinel\n')
        self.assertTrue(patched.endswith(b'# cloud runtime sentinel\n'))
        self.assertIn(b'unset ARTEX_PG_DSN ARTEX_SETUP_TOKEN NETWORKPNTR_LOCAL_SESSION_CAPABILITY', patched)
        with self.assertRaises(ValueError):
            patch_init(patched)
        with self.assertRaises(ValueError):
            patch_init(source.replace(b'read -r operation', b'read -r unknown'))

    def test_shell_protocol_accepts_only_independent_bounded_frames(self):
        a, b, c = 'a' * 64, 'b' * 64, 'c' * 64
        cases = [
            (f'ARTEX_BOOTSTRAP {a} {b}', True, False),
            (f'NETWORKPNTR_BOOTSTRAP_2 {a} {b} {c}', True, True),
            (f'NETWORKPNTR_BOOTSTRAP_2 {a} {b} {a}', False, False),
            (f'NETWORKPNTR_BOOTSTRAP_2 {a} {b} {c} extra', False, False),
            (f'NETWORKPNTR_BOOTSTRAP_2 {a} {b}', False, False),
            (f'ARTEX_BOOTSTRAP {a} {b} {c}', False, False),
            (f'ARTEX_BOOTSTRAP {a} {a}', False, False),
            (f'NETWORKPNTR_BOOTSTRAP_2 {a} {b} '+ 'C' * 64, False, False),
        ]
        program = 'set -eu\nfail() { exit 19; }\n' + NEW + '\n[ -z "${NETWORKPNTR_LOCAL_SESSION_CAPABILITY:-}" ] || exit 7\n'
        env = {k: v for k, v in os.environ.items() if k != 'NETWORKPNTR_LOCAL_SESSION_CAPABILITY'}
        for frame, allowed, native in cases:
            with self.subTest(allowed=allowed, native=native):
                result = subprocess.run(['/bin/sh', '-c', program], input=(frame + '\n').encode(), env=env, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 7 if native else 0 if allowed else 19)
                self.assertEqual(result.stdout + result.stderr, b'')

    def test_composite_manifest_replaces_stale_backend_identity_and_retains_parent(self):
        old = {'managedBackend': {'binarySHA256': 'old-binary', 'buildVersion': 'old-version', 'platform': 'linux/arm64', 'deployed': True}}
        manifest = dict(old, backendSHA256='new-binary')
        refresh_composite_metadata(manifest, old)
        self.assertEqual(manifest['managedBackend']['binarySHA256'], 'new-binary')
        self.assertEqual(manifest['managedBackend']['buildVersion'], 'dev')
        self.assertFalse(manifest['managedBackend']['deployed'])
        self.assertEqual(manifest['nativeSessionParentManagedBackend'], old['managedBackend'])
        self.assertEqual(old['managedBackend']['binarySHA256'], 'old-binary')
        ordinary = {'backendSHA256': 'ordinary'}
        refresh_composite_metadata(ordinary, {})
        self.assertNotIn('managedBackend', ordinary)

    def test_cleanup_preserves_durable_input_and_disables_parent_pruning(self):
        runtime = 'sha256:' + 'a' * 64
        def command(*args, **kwargs):
            if args[:3] == ('image', 'inspect', runtime):
                return json.dumps([{'RepoTags': ['durable:input', 'owned:alias']}]).encode()
            if args[:2] == ('image', 'inspect'):
                return runtime.encode()
            self.assertEqual(args, ('image', 'rm', '--no-prune', 'owned:alias'))
            return b''
        with patch('build_local_session.docker', side_effect=command) as run:
            remove_owned_parent_alias(runtime, 'owned:alias', ['durable:input'])
        self.assertEqual(run.call_args.args, ('image', 'rm', '--no-prune', 'owned:alias'))

    def test_cleanup_refuses_missing_or_moved_input_reference(self):
        runtime = 'sha256:' + 'a' * 64
        for moved in (False, True):
            def command(*args, **kwargs):
                if args[:3] == ('image', 'inspect', runtime):
                    return json.dumps([{'RepoTags': ['durable:input'] if moved else []}]).encode()
                return b'sha256:changed'
            with patch('build_local_session.docker', side_effect=command) as run:
                with self.assertRaises(ValueError):
                    remove_owned_parent_alias(runtime, 'owned:alias', ['durable:input'])
                self.assertFalse(any(call.args[:2] == ('image', 'rm') for call in run.call_args_list))


if __name__ == '__main__':
    unittest.main()
