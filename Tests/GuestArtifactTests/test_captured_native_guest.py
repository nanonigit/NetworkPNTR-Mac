import importlib.util
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load():
    sys.path.insert(0, str(ROOT/'script'))
    try:
        spec = importlib.util.spec_from_file_location('captured_native_guest', ROOT/'script/captured_native_guest.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module
    finally:
        sys.path.pop(0)


class CapturedNativeGuestTests(unittest.TestCase):
    def test_host_guard_precedes_index_or_fixture_side_effects(self):
        m = load()
        with patch.object(m.fixture, 'environment', side_effect=RuntimeError('host')), patch.object(m.sqlite3,'connect') as db, patch.object(m.fixture,'prepare') as seed:
            with self.assertRaises(RuntimeError): m.prepare()
            db.assert_not_called(); seed.assert_not_called()

    def test_nonempty_capture_refuses_before_seed_or_listener(self):
        m = load()
        with patch.object(m.fixture,'environment'), patch.object(m.NativeIndex,'api',return_value={'total':1,'exchanges':[{}]}), patch.object(m.fixture,'prepare') as seed:
            with self.assertRaises(RuntimeError):m.prepare()
            seed.assert_not_called()

    def test_fixed_read_only_index_reads_metadata_without_modifying_database(self):
        m = load()
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'index.sqlite'
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE exchanges(id TEXT,ts INTEGER,host TEXT,method TEXT,url TEXT,status INTEGER,content_type TEXT,resp_len INTEGER)')
                db.execute('INSERT INTO exchanges VALUES(?,?,?,?,?,?,?,?)',('1792663200-0001',1792663200,'127.0.0.1','GET',m.fixture.TARGET+'00',200,'text/plain; charset=utf-8',0))
            before=path.read_bytes(); original=m.sqlite3.connect; connections=[]
            def connect(*args,**kwargs):
                self.assertEqual(args[0],path.as_uri()+'?mode=ro');self.assertTrue(kwargs['uri']);value=original(*args,**kwargs);connections.append(value);return value
            with patch.object(m,'INDEX',path), patch.object(m.fixture,'environment'), patch.object(m.sqlite3,'connect',side_effect=connect):
                result=m.NativeIndex().api('GET','/api/traffic?page=0&size=500')
            self.assertEqual(result['total'],1);self.assertEqual(result['exchanges'][0]['id'],'1792663200-0001');self.assertEqual(result['page'],0)
            self.assertEqual(path.read_bytes(),before)
            with self.assertRaises(sqlite3.ProgrammingError): connections[0].execute('SELECT 1')

    def test_routes_symlinks_and_excess_rows_fail_closed(self):
        m=load()
        with patch.object(m.fixture,'environment'),patch.object(m.sqlite3,'connect') as connect:
            for method,path in [('POST','/api/traffic?page=0&size=500'),('GET','/api/traffic?page=1&size=500'),('GET','https://example.test')]:
                with self.assertRaises(RuntimeError):m.NativeIndex().api(method,path)
            connect.assert_not_called()
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'real';target.write_bytes(b'not SQLite');link=Path(directory)/'index.sqlite';link.symlink_to(target)
            with patch.object(m,'INDEX',link),patch.object(m.fixture,'environment'),patch.object(m.sqlite3,'connect') as connect:
                with self.assertRaises(RuntimeError):m.NativeIndex().api('GET','/api/traffic?page=0&size=500')
                connect.assert_not_called()
            path=Path(directory)/'many.sqlite'
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE exchanges(id TEXT,ts INTEGER,host TEXT,method TEXT,url TEXT,status INTEGER,content_type TEXT,resp_len INTEGER)')
                db.executemany('INSERT INTO exchanges VALUES(?,?,?,?,?,?,?,?)',[(str(i),0,'127.0.0.1','GET','fixed',200,'text/plain',0) for i in range(30)])
            with patch.object(m,'INDEX',path),patch.object(m.fixture,'environment'):
                with self.assertRaises(RuntimeError):m.NativeIndex().api('GET','/api/traffic?page=0&size=500')

    def test_prepare_returns_compact_byte_manifest_and_fixed_identity(self):
        m=load();prepared={'records':[{}]*29,'manifest':m.fixture.exchange_manifest(),'counts':{'events':0}}
        with patch.object(m.fixture,'environment'),patch.object(m.NativeIndex,'api',return_value={'count':0,'total':0,'exchanges':[]}),patch.object(m.fixture,'prepare',return_value=prepared) as seed,patch.object(m.os,'getuid',return_value=1000):
            result=m.prepare()
            self.assertTrue(result['captured_native_fixture']);self.assertEqual(result['uid'],1000);self.assertEqual(result['finding_id'],9101);self.assertEqual(result['records'],29)
            self.assertEqual(len(result['manifest_sha256']),64);self.assertNotIn('exchanges',result)
            self.assertLess(len(json.dumps(result)),8192);seed.assert_called_once()

    def test_restart_audit_never_seeds_or_generates_exchanges(self):
        m=load()
        with patch.object(m.fixture,'environment'),patch.object(m.fixture,'read_records',return_value=[{}]*29),patch.object(m.fixture,'audit_activity',return_value={'events':0}) as activity,patch.object(m.fixture,'prepare') as seed,patch.object(m.os,'getuid',return_value=1000):
            result=m.audit();self.assertEqual(result['records'],29);self.assertTrue(result['captured_native_fixture']);activity.assert_called_once_with(1,2);seed.assert_not_called()


if __name__=='__main__':unittest.main()
