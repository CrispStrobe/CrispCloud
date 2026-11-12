#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check separate normal/first header occurrences against native DOC controls."""
import argparse
import gzip
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import zipfile

from oracle import ROOT, _xml, digest
from run import command, office_convert, parser_convert
from textbox_boundary_probe import CONTROLS, REL, W, authored_control, boxes


def _enabled(element):
    return element is not None and element.get('{' + W + '}val', 'true') not in ('0', 'false', 'off')


def header_occurrences(path):
    """Count each referenced part separately; never deduplicate equal text."""
    observation = boxes(path)
    with zipfile.ZipFile(path) as package:
        body, _ = _xml(package.read('word/document.xml'))
        sections = list(body.iter('{' + W + '}sectPr'))
        if len(sections) != 1:
            raise ValueError('The authored header control must have exactly one section.')
        rels, _ = _xml(package.read('word/_rels/document.xml.rels'))
        relationships = {element.get('Id'): element for element in rels}
        result = {'sha256': digest(path), 'titlePage': _enabled(sections[0].find('{' + W + '}titlePg')),
                  'headers': {}, 'alternateContent': observation['alternateContent']}
        used = set()
        for reference in sections[0].findall('{' + W + '}headerReference'):
            kind = reference.get('{' + W + '}type')
            if kind in result['headers'] or kind not in ('default', 'first', 'even'):
                raise ValueError('Invalid or duplicate header reference.')
            relation = relationships.get(reference.get('{' + REL + '}id'))
            if relation is None or relation.get('Type') != REL + '/header' or relation.get('TargetMode') == 'External':
                raise ValueError('The header must have an internal header relationship.')
            target = relation.get('Target', '')
            part = target.lstrip('/') if target.startswith('/') else str(PurePosixPath('word') / target)
            if '..' in PurePosixPath(part).parts or part not in package.namelist():
                raise ValueError('Unresolved header part.')
            used.add(part)
            result['headers'][kind] = {'part': part, 'boxes': [box for box in observation['boxes'] if box['part'] == part]}
        result['unreferencedBoxes'] = [box for box in observation['boxes'] if box['part'] not in used]
        return result


def check_occurrences(observation, expected, *, title_page, require_first):
    errors = []
    if observation['titlePage'] != title_page:
        errors.append('title-page activation changed')
    headers = observation['headers']
    for kind in ('default', 'first'):
        required = kind == 'default' or require_first
        value = headers.get(kind)
        if value is None:
            if required:
                errors.append('missing ' + kind + ' header occurrence')
            continue
        actual = [box['paragraphs'] for box in value['boxes']]
        if actual != [expected]:
            errors.append(f'{kind}: expected {[expected]!r}, got {actual!r}')
    if headers.get('even', {}).get('boxes') or observation['unreferencedBoxes']:
        errors.append('unexpected additional textbox occurrence')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', type=Path, required=True)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--existing-controls', type=Path)
    parser.add_argument('--existing-receipt', type=Path)
    args = parser.parse_args()
    if bool(args.existing_controls) != bool(args.existing_receipt):
        parser.error('Existing native controls require their exact hash-bound receipt.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    os.environ.setdefault('TMPDIR', str(output / 'tmp'))
    Path(os.environ['TMPDIR']).mkdir(parents=True, exist_ok=True)
    sources = sorted([*ROOT.joinpath('lib').rglob('*.dart'), ROOT / 'pubspec.lock',
                      Path(__file__).resolve(), ROOT / 'tool/fidelity/convert.dart',
                      ROOT / 'tool/fidelity/header_textbox_titlepage.dart',
                      ROOT / 'tool/fidelity/textbox_boundary_probe.py', ROOT / 'tool/fidelity/run.py',
                      ROOT / 'tool/fidelity/oracle.py'])
    hashes = {str(path.relative_to(ROOT)): digest(path) for path in sources}
    report = {'schema': 'legacy-doc-parser/header-textbox-alias-probe', 'version': 1,
              'parserCommit': command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip(),
              'parserWorktreeDirty': bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip()),
              'sourceFiles': hashes, 'compiler': command([args.dart, '--version']).strip(),
              'renderer': command([args.office, '--version']).strip(), 'controls': [], 'errors': [],
              'method': 'Stored header occurrences are compared separately. Only SFTitlePage changes for first-page controls; no chain IDs or text ranges are changed.'}
    baseline = None
    try:
        if args.existing_receipt:
            with gzip.open(args.existing_receipt, 'rt') as source:
                baseline = {case['id']: case for case in json.load(source)['controls']}
            report['baselineReceiptSha256'] = digest(args.existing_receipt)
        converter, activation = output / 'convert', output / 'activate-first'
        command([args.dart, 'compile', 'exe', 'tool/fidelity/convert.dart', '-o', converter], cwd=ROOT)
        command([args.dart, 'compile', 'exe', 'tool/fidelity/header_textbox_titlepage.dart', '-o', activation], cwd=ROOT)
        report['converterSha256'], report['activationControlSha256'] = digest(converter), digest(activation)
        for name, expected in CONTROLS.items():
            base = output / name
            base.mkdir()
            case = {'id': name, 'expectedParagraphsPerOccurrence': expected}
            report['controls'].append(case)
            authored, binary, native = base / 'authored.docx', base / 'source.doc', base / 'native.docx'
            if baseline is not None:
                before = baseline['header-' + name]
                paths = [(args.existing_controls / ('header-' + name) / 'authored.docx', authored, before['authored']['sha256']),
                         (args.existing_controls / ('header-' + name) / 'bridge/authored.doc', binary, before['binarySha256']),
                         (args.existing_controls / ('header-' + name) / 'native/authored.docx', native, before['native']['sha256'])]
                for source, target, expected_hash in paths:
                    if digest(source) != expected_hash:
                        raise ValueError('Existing header control differs from its sealed receipt: ' + name)
                    shutil.copyfile(source, target)
                case['baselineParserError'] = before.get('parserError')
            else:
                authored_control(authored, expected, header=True)
                shutil.copyfile(office_convert(args.office, authored, base / 'bridge', 'doc'), binary)
                shutil.copyfile(office_convert(args.office, binary, base / 'native', 'docx'), native)
            input_hashes = {path.name: digest(path) for path in (authored, binary, native)}
            case['inputSha256'] = input_hashes
            converted, enabled = base / 'converted.docx', base / 'first-enabled.doc'
            case['converter'] = parser_convert(converter, binary, converted)
            case['activationControl'] = json.loads(command([activation, binary, enabled]))
            case['firstEnabledBinarySha256'] = digest(enabled)
            active_native = office_convert(args.office, enabled, base / 'first-native', 'docx')
            active_converted = base / 'first-converted.docx'
            case['firstConverter'] = parser_convert(converter, enabled, active_converted)
            # Native projections of both parser routes test their editable OOXML.
            roundtrip = office_convert(args.office, converted, base / 'parser-native', 'docx')
            active_roundtrip = office_convert(args.office, active_converted, base / 'first-parser-native', 'docx')
            routes = [('authored', authored, False, False), ('native', native, False, False),
                      ('parser', converted, False, True), ('parserNative', roundtrip, False, False),
                      ('firstNative', active_native, True, True), ('firstParser', active_converted, True, True),
                      ('firstParserNative', active_roundtrip, True, True)]
            for route, path, title_page, require_first in routes:
                observation = header_occurrences(path)
                errors = check_occurrences(observation, expected, title_page=title_page, require_first=require_first)
                observation['matchesExpectedOccurrences'] = not errors
                case[route] = observation
                report['errors'].extend(f'{name}/{route}: {error}' for error in errors)
            case['inputsUnchanged'] = input_hashes == {path.name: digest(path) for path in (authored, binary, native)}
            if not case['inputsUnchanged']:
                report['errors'].append(name + ': source controls changed')
            # Checkpoint every completed control; later failures cannot erase it.
            (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        report['errors'].append(str(error))
    finally:
        report['sourceUnchanged'] = hashes == {str(path.relative_to(ROOT)): digest(path) for path in sources}
        if not report['sourceUnchanged']:
            report['errors'].append('Measured source changed during native probe.')
        report['passed'] = not report['errors'] and len(report['controls']) == len(CONTROLS)
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'controls': len(report['controls']), 'errors': report['errors']}, indent=2))
    return int(not report['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
