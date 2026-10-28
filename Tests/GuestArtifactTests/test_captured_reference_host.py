import base64
import hashlib
import importlib.util
import tempfile
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]


def load():
    sys.path.insert(0,str(ROOT/'script'))
    try:
        spec=importlib.util.spec_from_file_location('captured_reference_host',ROOT/'script/captured_reference_host.py')
        m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
    finally:sys.path.pop(0)


class CapturedReferenceHostTests(unittest.TestCase):
    def test_import_is_inert_and_only_unix_context_is_local(self):
        with patch('subprocess.run') as run:
            m=load();run.assert_not_called()
        self.assertTrue(m.local_context('unix:///Users/fixture/.docker/run/docker.sock'))
        for endpoint in ['tcp://127.0.0.1:2375','ssh://host','unix://relative','unix:///tmp/a\nother']:
            self.assertFalse(m.local_context(endpoint))

    def test_create_contract_has_no_network_host_mounts_or_privilege(self):
        m=load();args=m.create_arguments('f5-test','a'*32,'f5-image:owned')
        self.assertEqual(args[args.index('--network')+1],'none')
        self.assertEqual(args[args.index('--user')+1],'1000:1000')
        self.assertIn('--read-only',args);self.assertIn('ALL',args);self.assertIn('no-new-privileges',args)
        self.assertNotIn('--privileged',args);self.assertNotIn('-v',args);self.assertNotIn('-p',args)
        with self.assertRaises(RuntimeError):m.create_arguments('unsafe\nname','a'*32,'f5-image:owned')

    def test_parent_alias_is_retained_when_any_original_tag_is_missing_or_retargeted(self):
        m=load();removed=[]
        images={'sha256:parent':{'Id':'sha256:parent','RepoTags':['original:one']},'original:one':{'Id':'sha256:parent'},'owned:alias':{'Id':'sha256:parent'}}
        m.remove_input_alias('owned:alias','sha256:parent',['original:one'],images.__getitem__,removed.append)
        self.assertEqual(removed,['owned:alias'])
        for bad in [{'sha256:parent':{'Id':'sha256:parent','RepoTags':[]}}, {'original:one':{'Id':'sha256:other'}}, {'owned:alias':{'Id':'sha256:other'}}]:
            removed.clear();state=dict(images);state.update(bad)
            with self.assertRaises(RuntimeError):m.remove_input_alias('owned:alias','sha256:parent',['original:one'],state.__getitem__,removed.append)
            self.assertEqual(removed,[])

    def test_source_bundle_and_hashes_are_frozen_before_later_file_edits(self):
        m=load()
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'fixture.py';path.write_bytes(b'before')
            snapshot=m.freeze_sources({'fixture.py':path});path.write_bytes(b'after')
            self.assertEqual(base64.b64decode(snapshot['bundle']['fixture.py']),b'before')
            self.assertEqual(snapshot['hashes']['fixture.py'],hashlib.sha256(b'before').hexdigest())
            self.assertNotEqual(snapshot['hashes']['fixture.py'],hashlib.sha256(path.read_bytes()).hexdigest())

    def test_install_and_execute_are_compilable_and_fixed_source_set(self):
        m=load();compile(m.INSTALL,'install','exec');compile(m.EXECUTE,'execute','exec')
        self.assertEqual(set(m.sources()),{'captured_reference.py','captured_fixture_guest.py','evidence_export_reference.py','evidence_fixture_guest.py','findings_seed_guest.py','findings_fixture_control.py','check_network.py'})


if __name__=='__main__':unittest.main()
