#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify the retained PICMID controls without executing native documents."""
import hashlib
import io
import json
from pathlib import Path
import tarfile
import xml.etree.ElementTree as ET
import zipfile

HERE = Path(__file__).resolve().parent
RUNTIME = '78c88b357ad66934abf9b467e3903748b7742e3c'
EXPECTED = {
    'integral': [1440, 720], 'below-half': [1500, 499], 'half': [1501, 501],
    'above-half': [1502, 501], 'one-thousandth': [1002, 2000],
    'retained-emf-ratio': [8640, 5184], 'retained-wmf-ratio': [8640, 5184],
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inventory(data, entries):
    expected = {entry['path']: entry for entry in entries}
    require(len(expected) == len(entries), 'Duplicate manifest member.')
    records = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as archive:
        for member in archive:
            require(member.isfile() and member.name not in records, 'Invalid or duplicate member.')
            require(member.name in expected, 'Unexpected archive member: ' + member.name)
            raw = archive.extractfile(member).read()
            receipt = expected[member.name]
            require(len(raw) == receipt['bytes'] and sha(raw) == receipt['sha256'],
                    'Artifact bytes differ: ' + member.name)
            records[member.name] = raw
    require(records.keys() == expected.keys(), 'Missing archive member.')
    return records


def extent(data):
    with zipfile.ZipFile(io.BytesIO(data)) as package:
        root = ET.fromstring(package.read('word/document.xml'))
    values = root.findall('.//{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}extent')
    require(len(values) == 1, 'Expected exactly one image frame.')
    return [int(values[0].attrib[key]) for key in ('cx', 'cy')]


def verify():
    manifest = json.loads((HERE / 'control-artifacts.manifest.json').read_text())
    receipt = manifest['archive']
    data = (HERE / receipt['path']).read_bytes()
    require(len(data) == receipt['bytes'] and sha(data) == receipt['sha256'], 'Archive bytes differ.')
    records = inventory(data, manifest['files'])
    require(len(records) == manifest['fileCount'], 'Archive count differs.')
    require(sum(len(raw) for raw in records.values()) == manifest['totalBytes'], 'Archive total differs.')
    for prefix in ['baseline', 'final']:
        require((HERE / (prefix + '-report.json')).read_bytes() == records[prefix + '/report.json'],
                'Displayed report differs from archive: ' + prefix)
    final = json.loads(records['final/report.json'])
    baseline = json.loads(records['baseline/report.json'])
    require(final['parserCommit'] == manifest['runtimeCommit'] == RUNTIME, 'Runtime differs.')
    require(final['parserWorktreeDirty'] is False, 'Final runtime was not clean.')
    require(final['errors'] == [], 'Final run has errors.')
    require(final['cases'].keys() == baseline['cases'].keys() == EXPECTED.keys(), 'Control inventory differs.')
    model = json.loads(records['final/converted/model.json'])
    require(model.keys() == EXPECTED.keys(), 'Model inventory differs.')
    for name, twips in EXPECTED.items():
        case = final['cases'][name]
        emu = [value * 635 for value in twips]
        require(case['expectedTwips'] == twips and case['expectedEmu'] == emu, 'Expected size differs.')
        require(case['native']['extentEmu'] == case['parser']['extentEmu'] == emu, 'Recorded frame differs.')
        require(extent(records['final/converted/' + name + '.docx']) == emu, 'Parser XML frame differs.')
        require(extent(records['final/native-docx/' + name + '/' + name + '.docx']) == emu,
                'Native XML frame differs.')
        require(case['parserModel'] == model[name], 'Model report differs.')
        require([model[name]['widthTwips'], model[name]['heightTwips']] == twips,
                'Parser model frame differs.')
        require(model[name]['cropFixed16'] == [0, 0, 0, 0], 'Source crop was invented.')
        require(case['checksPass'] is True and case['parserMatchesAuthoredTwips'] is True
                and case['nativeMatchesAuthoredTwips'] is True, 'Final control did not pass.')
        require(sha(records['final/binary/' + name + '.doc']) == case['sourceSha256'], 'Binary hash differs.')
        require(records['baseline/binary/' + name + '.doc'] == records['final/binary/' + name + '.doc'],
                'Baseline and final inputs differ.')
    failed = {name for name, case in baseline['cases'].items()
              if not case['parserMatchesAuthoredTwips']}
    require(failed == {'half', 'above-half', 'one-thousandth', 'retained-emf-ratio'},
            'Baseline disagreement inventory differs.')
    require(b'"checks":51' in records['logs/media-web-78c88b3.run.log'], 'JavaScript acceptance missing.')
    require(b'+83: All tests passed!' in records['logs/picture-sizing-focused-tests.log'],
            'Scoped Dart acceptance missing.')
    print(f'Verified {len(records)} exact control artifacts; final 7/7 and baseline 3/7 frame matches.')


if __name__ == '__main__':
    verify()
