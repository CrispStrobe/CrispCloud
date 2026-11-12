#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check all seven retained first-header controls through three DOC imports."""
import argparse
import gzip
import json
import os
from pathlib import Path
import shutil
import subprocess

from header_textbox_alias_probe import check_occurrences, header_occurrences
from oracle import ROOT, digest
from run import command, office_convert, parser_convert
from textbox_boundary_probe import CONTROLS


def verify_import(observation, counts, expected):
    errors = check_occurrences(observation, expected, title_page=True, require_first=True)
    if counts.get('textboxes') != 2:
        errors.append('exactly two stored header occurrences must be emitted')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--office', type=Path, required=True)
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--controls', type=Path, required=True,
                        help='results/ from the sealed header-textbox-alias-inputs archive')
    parser.add_argument('--receipt', type=Path, required=True,
                        help='Exact hash-bound header-textbox-alias-native.json.gz receipt')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    os.environ.setdefault('TMPDIR', str(output / 'tmp'))
    Path(os.environ['TMPDIR']).mkdir(parents=True, exist_ok=True)
    sources = sorted([*ROOT.joinpath('lib').rglob('*.dart'), ROOT / 'pubspec.lock',
                      Path(__file__).resolve(), ROOT / 'tool/fidelity/convert.dart',
                      ROOT / 'tool/fidelity/header_textbox_alias_probe.py',
                      ROOT / 'tool/fidelity/textbox_boundary_probe.py',
                      ROOT / 'tool/fidelity/run.py', ROOT / 'tool/fidelity/oracle.py'])
    hashes = {str(path.relative_to(ROOT)): digest(path) for path in sources}
    report = {'schema': 'legacy-doc-parser/header-textbox-roundtrip-probe', 'version': 1,
              'parserCommit': command(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip(),
              'parserWorktreeDirty': bool(command(['git', 'status', '--porcelain'], cwd=ROOT).strip()),
              'sourceFiles': hashes, 'sourceReceiptSha256': digest(args.receipt),
              'compiler': command([args.dart, '--version']).strip(),
              'renderer': command([args.office, '--version']).strip(),
              'roundtripCycles': 3, 'controls': [], 'errors': [],
              'method': 'Exact retained first-enabled DOC inputs; separate normal/first occurrences and intentional blank paragraphs checked on initial import and three native DOC re-exports. Native DOCX projection of each parser output checks editable content. No exact-layout claim.'}

    def save():
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    try:
        with gzip.open(args.receipt, 'rt') as stream:
            baseline = {case['id']: case for case in json.load(stream)['controls']}
        converter = output / 'convert'
        command([args.dart, 'compile', 'exe', 'tool/fidelity/convert.dart', '-o', converter], cwd=ROOT)
        report['converterSha256'] = digest(converter)
        for name, expected in CONTROLS.items():
            original = args.controls / name / 'first-enabled.doc'
            original_hash = baseline[name]['firstEnabledBinarySha256']
            if digest(original) != original_hash:
                raise ValueError('Retained header input differs from sealed receipt: ' + name)
            case = {'id': name, 'inputSha256': original_hash, 'expectedParagraphs': expected,
                    'stages': [], 'errors': []}
            report['controls'].append(case)
            current = original
            try:
                for cycle in range(4):
                    folder = output / name / f'cycle-{cycle:02d}'
                    folder.mkdir(parents=True)
                    source = folder / 'source.doc'
                    shutil.copyfile(current, source)
                    stage = {'cycle': cycle, 'inputSha256': digest(source)}
                    case['stages'].append(stage)
                    converted = folder / 'converted.docx'
                    stage['parser'] = parser_convert(converter, source, converted)
                    observation = header_occurrences(converted)
                    stage['converted'] = observation
                    errors = verify_import(observation, stage['parser']['counts'], expected)
                    projected = office_convert(args.office, converted, folder / 'native-projection', 'docx')
                    stage['nativeProjection'] = header_occurrences(projected)
                    errors.extend(check_occurrences(stage['nativeProjection'], expected,
                                                    title_page=True, require_first=True))
                    stage['errors'] = errors
                    case['errors'].extend(f'cycle-{cycle:02d}: {error}' for error in errors)
                    if digest(source) != stage['inputSha256']:
                        raise ValueError('Native renderer modified the stage input.')
                    if cycle < 3:
                        current = office_convert(args.office, converted, folder / 'native-doc', 'doc')
                        stage['nextBinarySha256'] = digest(current)
                    save()
            except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
                case['errors'].append(str(error))
            case['inputsUnchanged'] = digest(original) == original_hash
            if not case['inputsUnchanged']:
                case['errors'].append('Retained source changed')
            if len(case['stages']) != 4 or any('nativeProjection' not in stage for stage in case['stages']):
                case['errors'].append('Initial import plus all three cycles must complete')
            case['passed'] = not case['errors']
            report['errors'].extend(name + ': ' + error for error in case['errors'])
            save()
            print(json.dumps({'id': name, 'passed': case['passed'], 'errors': case['errors']}), flush=True)
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        report['errors'].append(str(error))
    finally:
        report['sourceUnchanged'] = hashes == {str(path.relative_to(ROOT)): digest(path) for path in sources}
        if not report['sourceUnchanged']:
            report['errors'].append('Measured source changed during native probe')
        report['passed'] = not report['errors'] and len(report['controls']) == len(CONTROLS)
        save()
    return int(not report['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
