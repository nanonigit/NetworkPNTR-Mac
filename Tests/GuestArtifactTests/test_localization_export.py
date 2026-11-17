"""Portable resources must follow the authoritative two-language catalog."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LocalizationExportTests(unittest.TestCase):
    def module(self):
        path = ROOT / 'script/export_localizations.py'
        self.assertTrue(path.is_file(), 'Localization exporter missing')
        spec = importlib.util.spec_from_file_location('localization_export', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def testRealCatalogGeneratesOnlyTwoLocalesAndChecksCommittedBytes(self):
        module = self.module()
        resources = ROOT / 'Sources/NetworkPNTRCore/Resources'
        module.export(resources / 'Localizable.xcstrings', resources, check=True)
        for code in ('en', 'ja'):
            values = plistlib.loads((resources / f'{code}.lproj/Localizable.strings').read_bytes())
            self.assertEqual(values['shell.runtime'], 'Runtime' if code == 'en' else '実行環境')

    def testDeterministicOutputAndStaleDetectionPreserveLiteralStrings(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / 'catalog.json'
            value = 'literal **text**\n日本語 <tag> "quote" \\path'
            source.write_text(json.dumps({'sourceLanguage':'en','version':'1.0','strings':{'fixture':{'localizations':{'en':{'stringUnit':{'state':'translated','value':value}}}}}}))
            module.export(source, root, check=False)
            output = root / 'en.lproj/Localizable.strings'; first = output.read_bytes()
            self.assertEqual(plistlib.loads(first)['fixture'], value)
            self.assertEqual(plistlib.loads((root / 'ja.lproj/Localizable.strings').read_bytes()), {})
            module.export(source, root, check=True)
            module.export(source, root, check=False)
            self.assertEqual(output.read_bytes(), first)
            output.write_bytes(b'stale')
            with self.assertRaises(ValueError): module.export(source, root, check=True)
            self.assertEqual(output.read_bytes(), b'stale')

    def testUnsupportedCatalogShapesFailBeforeWriting(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / 'catalog.json'
            for item in [
                {'sourceLanguage':'ko','strings':{}},
                {'sourceLanguage':'en','strings':{'x':{'localizations':{'ko':{'stringUnit':{'state':'translated','value':'x'}}}}}},
                {'sourceLanguage':'en','strings':{'x':{'localizations':{'en':{'variations':{}}}}}},
                {'sourceLanguage':'en','strings':{'x':{'localizations':{'ja':{'stringUnit':{'state':'translated','value':'x'}}}}}},
                {'sourceLanguage':'en','strings':{'x':{'localizations':{'en':{'stringUnit':{'state':'new','value':'x'}}}}}},
            ]:
                item['version'] = '1.0'
                source.write_text(json.dumps(item))
                with self.assertRaises(ValueError): module.export(source, root, check=False)
                self.assertFalse((root / 'en.lproj').exists())


if __name__ == '__main__': unittest.main()
