#!/usr/bin/env python3
"""Verify an APK uses the exact retained release certificate, never a debug key."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess


def check_report(report, expected):
    expected = expected.replace(':', '').strip().lower()
    if not re.fullmatch('[0-9a-f]{64}', expected):
        raise ValueError('Expected release certificate SHA-256 is invalid')
    if re.search(r'CN\s*=\s*Android Debug', report, re.I):
        raise ValueError('Refusing a debug-signed APK')
    # apksigner <= 35 prints "Signer #1 certificate ..."; newer build-tools
    # print one "V2 Signer: certificate ..." (per scheme) block instead.
    counts = re.findall(r'^Number of signers:\s*(\d+)\s*$', report, re.M)
    signers = re.findall(
        r'^(?:Signer #(\d+)|V[\d.]+ Signer:) certificate SHA-256 digest:\s*([0-9a-fA-F:]+)\s*$',
        report, re.M)
    digests = {digest.replace(':', '').lower() for _, digest in signers}
    if (counts != ['1'] or not signers or len(digests) != 1
            or any(number not in ('', '1') for number, _ in signers)):
        summary = '\n'.join(line for line in report.splitlines() if not line.startswith('WARNING'))
        raise ValueError('Expected exactly one verified APK signer; apksigner reported:\n' + summary)
    actual = digests.pop()
    if actual != expected:
        raise ValueError('APK signer differs from the retained release key; refusing an incompatible update')
    return actual


def expected_certificate(certificate, pin):
    digest = hashlib.sha256(certificate).hexdigest()
    pin = pin.replace(':', '').strip().lower()
    if not re.fullmatch('[0-9a-f]{64}', pin) or digest != pin:
        raise ValueError('Configured keystore does not match the previously published CrispCloud release certificate')
    return digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--certificate', type=Path, required=True, help='DER certificate exported from the retained keystore alias')
    parser.add_argument('--apksigner')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--certificate-only', action='store_true')
    parser.add_argument('--pinned-fingerprint-file', type=Path, default=Path(__file__).resolve().parents[1] / 'android/release-signing-cert.sha256')
    args = parser.parse_args()
    try:
        expected = expected_certificate(args.certificate.read_bytes(), args.pinned_fingerprint_file.read_text())
        if args.certificate_only:
            print('Retained Android release certificate matches the published identity: ' + expected)
            return
        if not args.apk or not args.apksigner or not args.output:
            parser.error('--apk, --apksigner and --output are required for APK verification')
        report = subprocess.check_output([args.apksigner, 'verify', '--verbose', '--print-certs', str(args.apk)], text=True)
        digest = check_report(report, expected)
        args.output.write_text(digest + '\n')
        print('APK signature verified against the retained release certificate: ' + digest)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Android release signing verification failed: {error}\n')


if __name__ == '__main__':
    main()
