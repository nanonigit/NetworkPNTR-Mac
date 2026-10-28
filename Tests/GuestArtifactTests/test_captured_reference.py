import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load():
    sys.path.insert(0,str(ROOT/'script'))
    try:
        spec=importlib.util.spec_from_file_location('captured_reference',ROOT/'script/captured_reference.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
    finally: sys.path.pop(0)


class CapturedReferenceTests(unittest.TestCase):
    def test_fixed_routes_reject_unrelated_writes_and_external_destinations(self):
        m=load()
        self.assertTrue(m.valid('GET','/api/traffic?page=0&size=25',None))
        self.assertTrue(m.valid('POST',m.BASE,{'traffic_refs':[{'traffic_id':'1792663200-0001','role':'proof','note':'literal'}]}))
        for method,path,body in [('POST','/api/tasks',{}),('GET','https://fixture.invalid/',None),('GET',m.BASE+'/%2f',None),('GET','/api/traffic?page=9999&size=25',None),('POST',m.BASE,{'traffic_refs':[{'traffic_id':'../secret'}]})]:
            self.assertFalse(m.valid(method,path,body))

    def test_preview_oracle_handles_split_utf8_empty_and_binary_without_normalization(self):
        m=load();text='e\u0301'.encode()*3001
        page=m.preview_expected(text,0)
        self.assertEqual(page['next_offset'],8191);self.assertFalse(page['binary'])
        tail=m.preview_expected(text,page['next_offset'])
        self.assertEqual((page['content']+tail['content']).encode(),text)
        self.assertTrue(m.preview_expected(bytes(range(256)),0)['binary'])
        self.assertEqual(m.preview_expected(b'',0)['total'],0)
        with self.assertRaises(RuntimeError): m.preview_expected(b'abc',4)

    def test_main_rejects_host_before_starting_backend(self):
        m=load()
        with patch.object(m.fixture,'environment',side_effect=RuntimeError('guard')),patch.object(m.subprocess,'Popen') as process:
            with self.assertRaises(RuntimeError): m.main()
            process.assert_not_called()


if __name__=='__main__':unittest.main()
