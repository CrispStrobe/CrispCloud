#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check independently specified visible text through isolated native imports.

This deliberately measures text, not page geometry or Microsoft Word fidelity.
Each case supplies its expectation before import. Raw PDFs, extracted text,
intermediate DOCX files and hashes remain available even when a case fails.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

from run import command, office_convert


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normalized(text):
    """Ignore only Unicode whitespace; preserve punctuation and all other text."""
    return re.sub(r'\s+', '', text)


def load_cases(manifest):
    data = json.loads(manifest.read_text())
    cases = data.get('cases')
    if not isinstance(cases, list) or not cases:
        raise ValueError('A nonempty cases array is required.')
    seen = set()
    result = []
    for case in cases:
        name = case.get('name')
        if (not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]*', name)
                or name in seen):
            raise ValueError('Case names must be unique safe directory names.')
        seen.add(name)
        expected = case.get('expectedText')
        if not isinstance(expected, str) or not isinstance(case.get('input'), str):
            raise ValueError('Each case needs an input path and expectedText string.')
        source = (manifest.parent / case['input']).resolve()
        if not source.is_file() or source.suffix.lower() not in ('.doc', '.docx', '.docm'):
            raise ValueError('Missing or unsupported native input: ' + str(source))
        result.append({'name': name, 'source': source, 'input': case['input'],
                       'expectedText': expected})
    return result


def probe(case, output, office, rounds):
    source = case['source']
    target = output / case['name']
    target.mkdir()
    record = {'name': case['name'], 'input': case['input'],
              'inputSha256': digest(source), 'inputKind': source.suffix.lower(),
              'expectedText': case['expectedText'],
              'normalizedExpectedText': normalized(case['expectedText']),
              'rounds': [], 'passed': False}
    current = source
    try:
        for index in range(1, rounds + 1):
            stage = {'round': index, 'inputSha256': digest(current)}
            record['rounds'].append(stage)
            pdf = office_convert(office, current, target / f'render-{index}', 'pdf')
            text = command(['pdftotext', '-enc', 'UTF-8', pdf, '-'])
            text_path = pdf.with_suffix('.txt')
            text_path.write_text(text)
            actual = normalized(text)
            stage.update({'pdf': str(pdf.relative_to(output)), 'pdfSha256': digest(pdf),
                          'text': str(text_path.relative_to(output)),
                          'textSha256': digest(text_path), 'actualText': text,
                          'normalizedActualText': actual,
                          'passed': actual == record['normalizedExpectedText']})
            # Save each native intermediate separately so a later successful
            # render cannot overwrite the evidence for an earlier discrepancy.
            if index < rounds:
                current = office_convert(office, current, target / f'docx-{index}', 'docx')
                stage.update({'nativeDocx': str(current.relative_to(output)),
                              'nativeDocxSha256': digest(current)})
            (target / 'report.json').write_text(json.dumps(record, indent=2) + '\n')
        record['passed'] = all(stage['passed'] for stage in record['rounds'])
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        record['error'] = str(error)
    (target / 'report.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--office', default='soffice')
    parser.add_argument('--rounds', type=int, default=3, choices=range(1, 6))
    parser.add_argument('--jobs', type=int, default=2, choices=range(1, 9))
    args = parser.parse_args(argv)
    manifest = args.manifest.resolve()
    cases = load_cases(manifest)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {'schema': 'legacy-doc-parser/native-text-probe', 'version': 1,
              'scope': 'Visible text after LibreOffice import; Unicode whitespace ignored. '
                       'No page geometry or Microsoft Word fidelity claim.',
              'manifestSha256': digest(manifest), 'probeSha256': digest(Path(__file__)),
              'office': args.office, 'officeVersion': command([args.office, '--version']).strip(),
              'requestedRounds': args.rounds, 'cases': []}

    def save():
        report['cases'].sort(key=lambda case: case['name'])
        report['completedCases'] = len(report['cases'])
        report['passedCases'] = sum(case['passed'] for case in report['cases'])
        report['passed'] = len(report['cases']) == len(cases) and report['passedCases'] == len(cases)
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    save()
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(probe, case, output, args.office, args.rounds) for case in cases]
        for future in as_completed(futures):
            record = future.result()
            report['cases'].append(record)
            save()
            print(json.dumps({'case': record['name'], 'passed': record['passed'],
                              'rounds': len(record['rounds']), 'error': record.get('error')}), flush=True)
    print(json.dumps({'cases': report['completedCases'], 'passed': report['passedCases'],
                      'allPassed': report['passed']}), flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
