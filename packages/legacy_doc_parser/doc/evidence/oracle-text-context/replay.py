#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Replay the exact sealed DOCX inputs through old/current text oracles.

No native renderer is run and no source, historical report or golden is edited.
Requires only Python's standard library and the recorded before Git object.
"""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import xml.etree.ElementTree as ET
import zipfile

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[2]
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def projection(value):
    main = next(story for story in value['stories'] if story['kind'] == 'main')
    paragraphs = next(group['items'] for group in value['paragraphs'] if group['story'] == 'main')
    revisions = next((group['items'] for group in value['revisions'] if group['story'] == 'main'), [])
    anchors = next((group['items'] for group in value['commentAnchors'] if group['story'] == 'main'), [])
    return {'oracleSchemaVersion': value['oracleSchemaVersion'], 'mainText': main['text'],
            'mainTextWithDeletions': main['textWithDeletions'],
            'paragraphTexts': [paragraph['text'] for paragraph in paragraphs],
            'paragraphProperties': [paragraph['properties'] for paragraph in paragraphs],
            'revisionOffsets': {item['kind']: item['offsetInParagraph'] for item in revisions},
            'revisions': revisions, 'commentOffsets': [item['offsetInParagraph'] for item in anchors]}


def replay(output):
    manifest = json.loads((BASE / 'inputs.json').read_text())
    before = manifest['beforeCommit']
    if not re.fullmatch('[0-9a-f]{40}', before):
        raise ValueError('Invalid before commit')
    output.mkdir(parents=True, exist_ok=False)
    inputs = output / 'inputs'
    inputs.mkdir()
    compressed = (BASE / 'inputs.tar.xz').read_bytes()
    if sha(compressed) != manifest['archiveSha256']:
        raise ValueError('Input archive changed')
    with tarfile.open(fileobj=io.BytesIO(lzma.decompress(compressed)), mode='r:') as archive:
        members = archive.getmembers()
        if [member.name for member in members] != sorted(manifest['inputs']):
            raise ValueError('Input archive inventory changed')
        for member in members:
            expected = manifest['inputs'][member.name]
            if not member.isreg() or Path(member.name).name != member.name:
                raise ValueError('Unsafe input archive entry')
            data = archive.extractfile(member).read()
            if len(data) != expected['bytes'] or sha(data) != expected['sha256']:
                raise ValueError('Input differs from the sealed source bytes')
            (inputs / member.name).write_bytes(data)
    results, source_hashes = {}, {}
    # Separate interpreters prevent either version from sharing imported
    # helper modules with the other version during this differential replay.
    child = ('import json,sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); '
             'from oracle import snapshot; '
             'print(json.dumps({Path(path).name:snapshot(path) for path in sys.argv[2:]}))')
    for version in ('before', 'after'):
        directory = output / version
        directory.mkdir()
        source_hashes[version] = {}
        for name in ('oracle.py', 'structure.py'):
            path = 'tool/fidelity/' + name
            data = (subprocess.check_output(['git', 'show', before + ':' + path], cwd=ROOT)
                    if version == 'before' else (ROOT / path).read_bytes())
            (directory / name).write_bytes(data)
            source_hashes[version][path] = sha(data)
        result = subprocess.check_output([sys.executable, '-c', child, str(directory),
                                          *(str(inputs / name) for name in sorted(manifest['inputs']))], text=True)
        results[version] = json.loads(result)
    report = {'schema': 'legacy-doc-parser/oracle-text-context-replay', 'version': 1,
              'beforeCommit': before, 'sourceHashes': source_hashes,
              'inputArchiveSha256': manifest['archiveSha256'], 'nativeRendererRun': False, 'cases': []}
    for name, expected in manifest['expected'].items():
        with zipfile.ZipFile(inputs / name) as package:
            tree = ET.fromstring(package.read('word/document.xml'))
        prior, actual = (projection(results[version][name]) for version in ('before', 'after'))
        case = {'input': name, 'sha256': manifest['inputs'][name]['sha256'],
                'propertyTabStops': len(tree.findall('.//' + W + 'tabs/' + W + 'tab')),
                'actualRunTabs': len(tree.findall('.//' + W + 'r/' + W + 'tab')),
                'expected': expected, 'before': prior, 'after': actual,
                'beforeMatchesExpected': all(prior[key] == value for key, value in expected.items()),
                'afterMatchesExpected': all(actual[key] == value for key, value in expected.items()),
                'paragraphPropertiesPreserved': prior['paragraphProperties'] == actual['paragraphProperties']}
        report['cases'].append(case)
    report['inputBytesUnchanged'] = all(sha((inputs / name).read_bytes()) == value['sha256']
                                      for name, value in manifest['inputs'].items())
    report['sourceBytesUnchanged'] = all(sha((ROOT / name).read_bytes()) == value
                                       for name, value in source_hashes['after'].items())
    report['passed'] = (report['inputBytesUnchanged'] and report['sourceBytesUnchanged']
                        and all(case['afterMatchesExpected'] and not case['beforeMatchesExpected']
                                and case['paragraphPropertiesPreserved'] for case in report['cases']))
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = replay(args.output.resolve())
    print(json.dumps({'passed': result['passed'], 'cases': len(result['cases']),
                      'receipt': str(args.output / 'report.json')}, indent=2))
    raise SystemExit(int(not result['passed']))
