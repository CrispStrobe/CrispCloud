#!/usr/bin/env python3
"""Verify actual Dart PNG-carving ZIPs using Python zipfile, zlib and Pillow.

Expected hashes, offsets and decoded pixels come from the independently
produced fixture manifest. No identity supplied by Dart is an oracle value.
"""
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 CrispCloud contributors
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import zipfile

from PIL import Image


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify(receipt, manifest):
    candidates = receipt['candidates']
    expected_cases = manifest['cases']
    if set(candidates) != set(expected_cases):
        raise ValueError('Candidate fixture inventory differs')
    checked = []
    for name, source in expected_cases.items():
        data = base64.b64decode(candidates[name], validate=True)
        expected = [c for c in source['candidates'] if c['status'] == 'recoverable']
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            names = [c['outputName'] for c in expected] + ['recovery-report.json']
            if archive.namelist() != names or archive.testzip() is not None:
                raise ValueError(f'ZIP namespace or CRC mismatch: {name}')
            for c in expected:
                info = archive.getinfo(c['outputName'])
                if info.flag_bits & 1 or info.is_dir():
                    raise ValueError('Unexpected encrypted/nonregular output')
                png = archive.read(info)
                if len(png) != c['bytes'] or sha(png) != c['sha256']:
                    raise ValueError(f'Carved source bytes mismatch: {name}')
                with Image.open(io.BytesIO(png)) as image:
                    image.verify()
                with Image.open(io.BytesIO(png)) as image:
                    image.load()
                    actual = {'mode': image.mode, 'width': image.width, 'height': image.height,
                              'pixels_sha256': sha(image.tobytes())}
                if actual != {key: c[key] for key in actual}:
                    raise ValueError(f'Independent PNG decoding mismatch: {name}')
            report = json.loads(archive.read('recovery-report.json'))
            if report['sourceSha256'] != source['sha256'] or report['source']['bytes'] != source['bytes']:
                raise ValueError('Report source binding mismatch')
            if report['stopReason'] != 'endOfInput' or report['scannedBytes'] != source['bytes']:
                raise ValueError('Report coverage mismatch')
            if report['unreadableRanges'] or report['unscannedRanges']:
                raise ValueError('Report invented missing source regions')
            if len(report['candidates']) != len(source['candidates']):
                raise ValueError('Report candidate inventory mismatch')
            for reported, exp in zip(report['candidates'], source['candidates']):
                if any(reported[key] != exp[key] for key in ['offset', 'status', 'reason']):
                    raise ValueError('Report candidate classification mismatch')
                valid = exp['status'] == 'recoverable'
                if reported['selected'] != valid or reported['rangeValidated'] != valid:
                    raise ValueError('Report authorizes an invalid range')
                if valid and any(reported[key] != exp[key] for key in ['sha256', 'endExclusive', 'outputName']):
                    raise ValueError('Report candidate identity mismatch')
        checked.append({'name': name, 'archiveBytes': len(data), 'archiveSha256': sha(data), 'verifiedPngs': len(expected)})
    return checked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidates', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    manifest_path = root / 'test/fixtures/archives/png-carving-reference-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    receipt = json.loads(args.candidates.read_text())
    checked = verify(receipt, manifest)
    # A negative control proves wrong expected output bytes are rejected even
    # if a valid ZIP and internally self-consistent report accompany them.
    wrong = json.loads(json.dumps(manifest))
    first = next(c for row in wrong['cases'].values() for c in row['candidates'] if c['status'] == 'recoverable')
    first['sha256'] = '0' * 64
    try:
        verify(receipt, wrong)
    except ValueError:
        negative = True
    else:
        raise ValueError('Oracle accepted changed expected source hash')
    report = {'schema': 1, 'oracle': 'Python zipfile CRC + exact source SHA256 + Pillow decoded pixels',
              'fixtureManifestSha256': sha(manifest_path.read_bytes()),
              'candidateReceiptSha256': sha(args.candidates.read_bytes()),
              'cases': checked, 'passed': len(checked),
              'verifiedPngs': sum(row['verifiedPngs'] for row in checked),
              'wrongExpectedHashRejected': negative}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['passed', 'verifiedPngs', 'wrongExpectedHashRejected']}))


if __name__ == '__main__':
    main()
