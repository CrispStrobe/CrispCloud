#!/usr/bin/env python3
"""Verify the exact retained portable baseline without extracting its archive."""
import hashlib
import json
from pathlib import Path
import tarfile


root = Path(__file__).resolve().parent
manifest = json.loads((root / 'manifest.json').read_text())
archive = root / manifest['archive']['path']
assert archive.stat().st_size == manifest['archive']['size']
assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest['archive']['sha256']
with tarfile.open(archive) as source:
    members = source.getmembers()
    assert len({item.name for item in members}) == len(members)
    assert {item.name for item in members} == set(manifest['members'])
    for item in members:
        assert item.isfile() and '/' not in item.name and item.name not in ('.', '..')
        data = source.extractfile(item).read()
        expected = manifest['members'][item.name]
        assert len(data) == expected['size']
        assert hashlib.sha256(data).hexdigest() == expected['sha256']
    receipt = json.load(source.extractfile('receipt.json'))
    assert receipt['commit'] == manifest['runtimeCommit']
    assert receipt['tree'] == manifest['runtimeTree']
    assert receipt['success'] and receipt['inputsUnchanged']
    assert receipt['inputsBefore'] == receipt['inputsAfter']
    assert len(receipt['inputsBefore']) == manifest['inputFiles']
    assert receipt['dirtyBefore'] == receipt['dirtyAfter'] == ''
    assert len(receipt['stages']) == 8
    for stage in receipt['stages']:
        assert stage['exitCode'] == 0
        assert manifest['members'][stage['log']]['sha256'] == stage['logSha256']
print(json.dumps({'verified': True, 'runtime': manifest['runtimeCommit'],
                  'members': len(members), 'inputsUnchanged': manifest['inputFiles']}))
