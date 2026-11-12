#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Measure section-review retention without treating native loss as a golden."""
import argparse
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

from oracle import ROOT, digest
from run import command, office_convert

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
SOURCE_SHA256 = '3f9955f4ddb65742da0f251c3cdf8ae0934defbfcd7c415a7954bfce37eafe32'
EXPECTED = {'sourceAuthor': 'Alice', 'sourceDate': '2026-11-12T08:45:00',
            'firstSectionCurrentLeft': 2880, 'firstSectionPriorLeft': 1440,
            'firstSectionCurrentColumns': 2, 'firstSectionPriorColumns': 1,
            'secondSectionCurrentBreak': 'nextPage',
            'secondSectionPriorBreak': 'continuous'}


def section_review(path):
    with zipfile.ZipFile(path) as package:
        document = ET.fromstring(package.read('word/document.xml'))
    parents = {child: parent for parent in document.iter() for child in parent}
    sections = []
    for section in document.iter('{' + W + '}sectPr'):
        if parents.get(section) is not None and parents[section].tag == '{' + W + '}sectPrChange':
            continue
        changes = section.findall('{' + W + '}sectPrChange')
        if len(changes) > 1:
            raise ValueError('A current section has more than one revision snapshot.')
        change = changes[0] if changes else None
        if change is not None and len(change.findall('{' + W + '}sectPr')) != 1:
            raise ValueError('A section revision must contain one previous section.')
        previous = None if change is None else change.find('{' + W + '}sectPr')

        def properties(node):
            return {child.tag.rsplit('}', 1)[-1]: {
                        key.rsplit('}', 1)[-1]: value for key, value in child.attrib.items()}
                    for child in node if child.tag != '{' + W + '}sectPrChange'}

        sections.append({'current': properties(section),
                         'previous': None if previous is None else properties(previous),
                         'revision': None if change is None else {
                             key.rsplit('}', 1)[-1]: value for key, value in change.attrib.items()}})
    return {'sha256': digest(path), 'sections': sections,
            'sectionRevisionCount': sum(section['revision'] is not None for section in sections)}


def verify_parser_review(review, source_sha256):
    """Assert authored DOC facts independently of either native import route."""
    if source_sha256 != SOURCE_SHA256:
        raise ValueError('Section-review source does not match the reviewed fixture receipt.')
    sections = review.get('sections', [])
    if len(sections) != 2 or review.get('sectionRevisionCount') != 2:
        raise ValueError('Parser must retain both current sections and both revision snapshots.')
    identifiers = set()
    for index, section in enumerate(sections):
        revision = section.get('revision')
        if (not isinstance(revision, dict)
                or revision.get('author') != EXPECTED['sourceAuthor']
                or revision.get('date') != EXPECTED['sourceDate']
                or not str(revision.get('id', '')).isdigit()):
            raise ValueError(f'Section {index + 1} lost its source review metadata.')
        identifiers.add(revision['id'])
        for state in ('current', 'previous'):
            properties = section.get(state)
            if not isinstance(properties, dict):
                raise ValueError(f'Section {index + 1} has no {state} properties.')
            expected = {
                ('pgSz', 'w'): '12240', ('pgSz', 'h'): '15840',
                ('pgMar', 'left'): str(2880 if index == 0 and state == 'current' else 1440),
                ('cols', 'num'): str(2 if index == 0 and state == 'current' else 1),
                ('type', 'val'): 'continuous' if index == 1 and state == 'previous' else 'nextPage',
            }
            for (element, attribute), value in expected.items():
                actual = properties.get(element, {}).get(attribute)
                if actual != value:
                    raise ValueError(
                        f'Section {index + 1} {state} {element}/@{attribute}: '
                        f'expected {value!r}, found {actual!r}.')
    if len(identifiers) != 2:
        raise ValueError('Section revision identifiers are not unique.')
    return {'passed': True, 'sourceReceiptSha256': SOURCE_SHA256,
            'currentSectionsChecked': 2, 'previousSectionsChecked': 2,
            'nativeOutputUsedAsExpected': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', required=True, type=Path)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = output / 'source.doc'
    converted = output / 'converted.docx'
    command([args.dart, 'run', 'tool/fidelity/section_review_fixture.dart', source], cwd=ROOT)
    source_hash = digest(source)
    adapter = command([args.dart, 'run', 'tool/fidelity/convert.dart', source, converted], cwd=ROOT)
    report = {
        'schema': 'legacy-doc-parser/section-review-probe', 'version': 1,
        'renderer': command([args.office, '--version']).strip(),
        'sourceSha256': source_hash,
        'converter': json.loads(adapter),
        'expected': EXPECTED,
        'ours': section_review(converted),
    }
    try:
        report['verification'] = verify_parser_review(report['ours'], source_hash)
    except ValueError as error:
        report['verification'] = {'passed': False, 'error': str(error)}
    for name, path in [('nativeSource', source), ('nativeConverted', converted)]:
        try:
            native = office_convert(args.office, path, output / name, 'docx')
            report[name] = section_review(native)
            report[name]['lostSectionRevisionCountFromOurs'] = (
                report['ours']['sectionRevisionCount'] - report[name]['sectionRevisionCount'])
        except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
            report[name] = {'error': str(error)}
    report['sourceUnchanged'] = digest(source) == source_hash
    report['method'] = ('Independently assembled DOC; native DOC and parser DOCX imports. '
                        'Renderer loss is reported and never accepted as expected review behavior.')
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value.get('sectionRevisionCount', value.get('error'))
                      for key, value in report.items()
                      if key in ('ours', 'nativeSource', 'nativeConverted')}, indent=2))
    return int(not report['sourceUnchanged'] or not report['verification']['passed'] or any(
        'error' in report[key] for key in ('nativeSource', 'nativeConverted')))


if __name__ == '__main__':
    raise SystemExit(main())
