#!/usr/bin/env python3
"""Verify retained receipt hashes and losslessly extract them if requested."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify(extract=None):
    receipt = json.loads((ROOT / 'receipt.json').read_text())
    raw = {}
    for name, expected in receipt['artifacts'].items():
        if Path(name).name != name or expected['encoding'] != 'gzip':
            raise ValueError('Unexpected artifact path or encoding')
        data = (ROOT / name).read_bytes()
        if len(data) != expected['bytes'] or digest(data) != expected['sha256']:
            raise ValueError('Compressed artifact mismatch: ' + name)
        decoded = gzip.decompress(data)
        if (len(decoded) != expected['uncompressedBytes']
                or digest(decoded) != expected['uncompressedSha256']):
            raise ValueError('Uncompressed artifact mismatch: ' + name)
        target = expected['uncompressedName']
        if Path(target).name != target or target in raw:
            raise ValueError('Unexpected or duplicate extraction path')
        raw[target] = decoded
    for name, expected in receipt.get('helpers', {}).items():
        if Path(name).name != name:
            raise ValueError('Unexpected helper path')
        data = (ROOT / name).read_bytes()
        if len(data) != expected['bytes'] or digest(data) != expected['sha256']:
            raise ValueError('Helper mismatch: ' + name)
    before = json.loads(raw['cohort-inputs-before.json'])
    summary = json.loads(raw['cohort-summary.json'])
    if raw['cohort-inputs-before.json'] != raw['cohort-inputs-after.json']:
        raise ValueError('The cohort input inventories differ')
    if (not summary['success'] or summary['testCount'] != 107
            or summary['executedSuiteCount'] != 8
            or not summary['cohortCompleteWithoutSkips']
            or not summary['sourceAndDependenciesUnchanged']):
        raise ValueError('Unexpected cohort result')
    for name, expected in summary['files'].items():
        decoded = raw['cohort-' + name]
        if len(decoded) != expected['bytes'] or digest(decoded) != expected['sha256']:
            raise ValueError('Original cohort receipt mismatch: ' + name)
    for original, retained in {
        'adapter/word_cohort.py': 'cohort-captured-runner.py',
        'adapter/pubspec.yaml': 'cohort-pubspec.yaml',
        'adapter/pubspec.lock': 'cohort-pubspec.lock',
        'adapter/.dart_tool/package_config.json': 'cohort-package-config.json',
    }.items():
        if digest(raw[retained]) != before['files'][original]['sha256']:
            raise ValueError('Captured runner configuration mismatch: ' + retained)
    native = json.loads(raw['native.json'])
    if len(native['checks']) != 13 or not all(native['checks'].values()):
        raise ValueError('Unexpected native check result')
    source = before['files']['app/test/fixtures/word_native/formatting.doc']
    if native['sourceSha256'] != source['sha256']:
        raise ValueError('Native input differs from the scoped source fixture')
    if extract is not None:
        extract.mkdir(parents=True, exist_ok=False)
        for name, data in raw.items():
            (extract / name).write_bytes(data)
    print(json.dumps({'verifiedArtifacts': len(raw),
                      'appSourceCommit': before['appCommit'],
                      'tests': summary['testCount'],
                      'unchangedInputFiles': before['fileCount'],
                      'nativeChecks': len(native['checks']),
                      'extracted': str(extract) if extract else None}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extract', type=Path, help='New, nonexistent directory')
    verify(parser.parse_args().extract)
