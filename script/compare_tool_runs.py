"""Compare the native service projection with the exact pinned API receipt."""
import argparse
import hashlib
import json
from pathlib import Path

REFERENCE = Path(__file__).resolve().parents[1] / 'evidence/tool-runs/pinned-browser-api.json'
REVIEWED_MANIFEST_SHA256 = '9c38d268d350e7ab4e265ca32d686c529d8e09e5facfc2c69581f31589b768d8'


def compare(reference_bytes, native):
    reference = json.loads(reference_bytes)
    if (native.get('sourceCommit') != reference['sourceCommit']
            or native.get('guestManifestSHA256') != REVIEWED_MANIFEST_SHA256
            or native.get('referenceSHA256') != hashlib.sha256(reference_bytes).hexdigest()
            or native.get('protectedStatuses') != reference['protectedStatuses']
            or not all(native.get(key) is True for key in ('freshEmpty', 'cooperativeStop', 'isolated'))):
        raise ValueError('Native tool history provenance or lifecycle proof differs')
    snapshots = native['snapshots']
    if set(snapshots) != set(reference['cases']):
        raise ValueError('Native tool history cases differ')
    cases = {}
    for name, expected in reference['cases'].items():
        snapshot = snapshots[name]
        if len(snapshot) != 2 or len(snapshot[0]) != expected['pagesChecked']:
            raise ValueError(f'Native tool history page coverage differs: {name}')
        digest = hashlib.sha256(json.dumps(snapshot, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        if digest != expected['snapshotSHA256']:
            raise ValueError(f'Native tool history snapshot differs: {name}')
        cases[name] = {'pagesChecked': expected['pagesChecked'], 'rows': expected['rows'], 'matchedSHA256': digest}
    return {key: native[key] for key in (
        'sourceCommit', 'referenceSHA256', 'guestManifestSHA256', 'protectedStatuses', 'freshEmpty',
        'cooperativeStop', 'isolated'
    )} | {'cases': cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('native_result', type=Path)
    args = parser.parse_args()
    with args.native_result.open('rb') as stream:
        native_bytes = stream.read(1024 * 1024 + 1)
    if len(native_bytes) > 1024 * 1024:
        raise ValueError('Native tool history receipt exceeds the comparison bound')
    print(json.dumps(compare(REFERENCE.read_bytes(), json.loads(native_bytes)), indent=2))


if __name__ == '__main__':
    main()
