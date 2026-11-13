#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Reseal altered evidence, then require the real verifier to reject it.

No production converter, Dart compiler or native renderer is run. Python -O
is propagated to each verification subprocess when selected by the caller.
"""
import argparse
import copy
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

import build_bundle
import verify


def change_json(data, path, change):
    value = json.loads(data[path])
    change(value)
    data[path] = (json.dumps(value, indent=2) + '\n').encode()


def set_report(data, path, key, value):
    change_json(data, path, lambda document: document.__setitem__(key, value))


def mutate_charset(data):
    path = 'font-metadata-counterfactuals-v2/wingdings-charset-01.docx'
    parts = verify.package_parts(data[path])
    parts['word/fontTable.xml'] = parts['word/fontTable.xml'].replace(b'w:val="01"', b'w:val="02"')
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as archive:
        for name, value in parts.items():
            archive.writestr(name, value)
    data[path] = output.getvalue()
    change_json(data, 'font-metadata-counterfactuals-v2/report.json',
                lambda doc: doc['cases'][1].__setitem__('packageSha256', verify.sha(data[path])))


def command_mutation(data):
    change_json(data, 'font-followup-validation-v2.json',
                lambda doc: next(item for item in doc['commands'] if item['label'] == 'targeted-tests').__setitem__('argv', ['dart', '--version']))


def missing_web_cohort(data):
    def change(doc):
        row = next(item for item in doc['commands'] if item['label'] == 'full-web')
        row['stdout'] = row['stdout'].replace('Ink header JavaScript acceptance passed:', 'Invented cohort:')
    change_json(data, 'font-followup-validation-v2.json', change)


def rebound_final_output(data):
    path = 'font-final-output-equivalence/initial.docx'
    data[path] = data['symbol-native-measurements/after.docx']
    change_json(data, 'font-final-output-equivalence/report.json',
                lambda doc: doc['cases'][0].__setitem__('sha256', verify.sha(data[path])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    original, manifest = verify.read_bundle(directory)
    controls = [
        ('missing-raw-raster', lambda d: d.pop('font-native-measurements/after-render/page-0001.ppm.gz'), 'page-0001.ppm.gz'),
        ('changed-source-control', lambda d: d.__setitem__('csymbol.doc', d['ordinary.doc']), 'Pinned binary control identity'),
        ('false-native-exactness', lambda d: change_json(d, 'font-native-measurements/report.json', lambda j: j['afterAgainstSource'].__setitem__('exactOnThisRenderer', False)), 'Native initial comparison'),
        ('erased-original-residual', lambda d: change_json(d, 'symbol-native-measurements/report.json', lambda j: j['afterAgainstSource'].__setitem__('maximumWordDriftPoints', 0)), 'Native initial comparison'),
        ('relabelled-old-snapshot', lambda d: set_report(d, 'note-joins-native-snapshot.json', 'oracleSchemaVersion', 6), 'Historical schema-5 snapshot'),
        ('changed-raw-font-charset', lambda d: change_json(d, 'symbol-font-source.json', lambda j: j['fonts'][6].__setitem__('charset', 1)), 'Raw symbol FFN'),
        ('changed-font-counterfactual', mutate_charset, 'Counterfactual charset operand'),
        ('changed-font-oracle-version', lambda d: set_report(d, 'font-charset-counterexample.json', 'currentOracleSchema', 5), 'Font oracle version'),
        ('rebound-final-package', rebound_final_output, 'Final output is not'),
        ('substituted-combined-source', lambda d: set_report(d, 'combined-source-equivalence/equivalence.json', 'combinedSourceCommit', verify.FINAL), 'Combined source identity'),
        ('invented-test-command', command_mutation, 'Targeted test identity'),
        ('missing-actual-js-cohort', missing_web_cohort, 'Missing actual full-web cohort'),
        ('invented-schema-pass', lambda d: change_json(d, 'font-schema-followup-validation.json', lambda j: j['Reports'][0]['Errors'].append({'Description': 'deliberate'})), 'Actual schema output binding'),
        ('erased-original-guard-failure', lambda d: set_report(d, 'font-guard-failure/report.json', 'exitCode', 0), 'Original font guard failure'),
    ]
    results = []
    with tempfile.TemporaryDirectory(prefix='symbol-font-evidence-', dir=args.repository.resolve()) as temporary:
        root = Path(temporary)
        for label, mutate, expected in controls:
            case = root / label
            case.mkdir()
            data = dict(original)
            mutate(data)
            sealed = copy.deepcopy(manifest)
            archive = case / 'observations.zip'
            with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1) as output:
                for name, value in data.items():
                    output.writestr(name, value)
            sealed['records'] = [{'path': name, 'sha256': verify.sha(value), 'bytes': len(value)} for name, value in sorted(data.items())]
            sealed['archive'] = {'path': archive.name, 'sha256': verify.sha(archive.read_bytes()), 'bytes': archive.stat().st_size}
            (case / 'manifest.json').write_text(json.dumps(sealed, indent=2) + '\n')
            for source in directory.iterdir():
                if source.is_file() and source.name not in ('manifest.json', 'observations.zip', 'checksums.json'):
                    shutil.copyfile(source, case / source.name)
            build_bundle.refresh_checksums(case)
            command = [sys.executable, *(['-O'] if sys.flags.optimize else []), str(case / 'verify.py'), '--repository', str(args.repository.resolve())]
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            if result.returncode == 0 or expected not in result.stderr:
                raise RuntimeError('Control was accepted or failed for the wrong reason: ' + label + '\n' + result.stdout + result.stderr)
            results.append({'control': label, 'rejected': True, 'expectedReason': expected})
            print('Rejected resealed control: ' + label, flush=True)
    print(json.dumps({'controls': len(results), 'optimizedPython': bool(sys.flags.optimize), 'results': results}, sort_keys=True))


if __name__ == '__main__':
    main()
