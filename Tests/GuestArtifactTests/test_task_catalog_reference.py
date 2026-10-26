import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / 'script'
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('catalog_reference', SCRIPTS / 'task_catalog_reference.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class CatalogReferenceTests(unittest.TestCase):
    def test_host_or_non_disposable_environment_refused_before_network(self):
        for system, uid, disposable in [('Darwin', 1000, '1'), ('Linux', 0, '1'), ('Linux', 1000, '')]:
            with patch.object(fixture.platform, 'system', return_value=system), patch.object(fixture.os, 'getuid', return_value=uid), patch.dict(fixture.os.environ, {'ARTEX_DISPOSABLE_REFERENCE': disposable}), patch.object(fixture, 'Client') as client:
                with self.assertRaises(RuntimeError):
                    fixture.main()
                client.assert_not_called()

    def test_missing_envelope_or_changed_unicode_linkage_refused(self):
        self.assertEqual(fixture.array({'templates': None}, 'templates'), [])
        for value in [{}, {'templates': {}}, []]:
            with self.assertRaises(RuntimeError):
                fixture.array(value, 'templates')
        draft = {'name': 'e\u0301', 'category_id': None}
        self.assertEqual(fixture.matching_template({'id': 8, **draft}, 8, draft)['id'], 8)
        for row in [{'id': 8, 'name': 'é', 'category_id': None}, {'id': 9, **draft}, {'id': 8, 'name': 'e\u0301', 'category_id': 8}]:
            with self.assertRaises(RuntimeError):
                fixture.matching_template(row, 8, draft)
