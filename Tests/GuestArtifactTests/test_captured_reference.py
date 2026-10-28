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

    def test_wrong_bound_record_or_source_identity_cannot_satisfy_body_gates(self):
        m=load();records=[{'id':str(1792663200)+'-%04d'%i,'url':row['url']} for i,row in enumerate(m.fixture.exchange_manifest())]
        good={'bindings':[{'id':str(i),'snapshot':{'source_traffic_id':records[n]['id'],'url':records[n]['url']}} for i,n in [(1,3),(2,4)]]}
        m.validate_bound_sources(good,records)
        import copy
        for field,value in [('url',records[1]['url']),('source_traffic_id',records[1]['id'])]:
            bad=copy.deepcopy(good);bad['bindings'][0]['snapshot'][field]=value
            with self.assertRaises(RuntimeError):m.validate_bound_sources(bad,records)

    def test_correct_filter_total_cannot_hide_wrong_rows(self):
        m=load();expected=[{'id':'one','url':'http://127.0.0.1:8799/f5-captured/01'}]
        good={'total':1,'count':29,'page':0,'size':500,'exchanges':expected}
        m.validate_filtered_page(good,expected)
        bad=dict(good,exchanges=[{'id':'other','url':'http://127.0.0.1:8799/f5-captured/02'}])
        with self.assertRaises(RuntimeError):m.validate_filtered_page(bad,expected)

    def test_picker_bind_defaults_use_empty_notes_and_the_exact_two_sources(self):
        m=load();records=[{'id':'1792663200-%04d'%i} for i in range(29)]
        refs=m.picker_refs(records)
        self.assertEqual(refs,[{'traffic_id':records[3]['id'],'role':'supporting','note':''},{'traffic_id':records[4]['id'],'role':'supporting','note':''}])

    def test_main_rejects_host_before_starting_backend(self):
        m=load()
        with patch.object(m.fixture,'environment',side_effect=RuntimeError('guard')),patch.object(m.subprocess,'Popen') as process:
            with self.assertRaises(RuntimeError): m.main()
            process.assert_not_called()


if __name__=='__main__':unittest.main()
