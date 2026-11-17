"""Derive portable resources from the single authoritative String Catalog."""
import argparse
import json
from pathlib import Path
import plistlib


def export(source, destination, *, check):
    catalog = json.loads(Path(source).read_text(encoding='utf-8'))
    if not isinstance(catalog, dict) or catalog.get('sourceLanguage') != 'en' or catalog.get('version') != '1.0' or not isinstance(catalog.get('strings'), dict):
        raise ValueError('Unsupported catalog root')
    values = {'en': {}, 'ja': {}}
    for key, entry in catalog['strings'].items():
        if not isinstance(key, str) or not key or not isinstance(entry, dict):
            raise ValueError('Invalid catalog key')
        locales = entry.get('localizations')
        if not isinstance(locales, dict) or 'en' not in locales or not set(locales) <= set(values):
            raise ValueError('Unsupported catalog locales')
        for code, localized in locales.items():
            if not isinstance(localized, dict) or set(localized) != {'stringUnit'}:
                raise ValueError('Unsupported localization variation')
            unit = localized['stringUnit']
            if not isinstance(unit, dict) or set(unit) != {'state', 'value'} or unit.get('state') != 'translated' or not isinstance(unit.get('value'), str):
                raise ValueError('Incomplete catalog translation')
            values[code][key] = unit['value']
    # Validate and serialize every locale before changing any generated file.
    generated = {Path(destination) / f'{code}.lproj/Localizable.strings': plistlib.dumps(items, sort_keys=True)
                 for code, items in values.items()}
    for path, content in generated.items():
        if check:
            if not path.is_file() or path.read_bytes() != content:
                raise ValueError('Generated localization resources are stale; run python3 script/export_localizations.py')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    resources = Path(__file__).resolve().parents[1] / 'Sources/NetworkPNTRCore/Resources'
    export(resources / 'Localizable.xcstrings', resources, check=arguments.check)
