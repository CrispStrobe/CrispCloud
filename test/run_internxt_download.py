#!/usr/bin/env python3
"""Run the Internxt adapter regression locally using only test-account credentials."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env-file', required=True, type=Path)
    args = parser.parse_args()
    if os.environ.get('CI') or os.environ.get('GITHUB_ACTIONS'):
        parser.error('Live account tests are local-only')
    selected = {}
    for line in args.env_file.read_text().splitlines():
        line = line.strip().removeprefix('export ')
        key, separator, value = line.partition('=')
        key = key.strip()
        if separator and key in {'INTERNXT_LOGIN_TESTS', 'INTERNXT_PW_TESTS'}:
            selected[key] = ' '.join(shlex.split(value, comments=True))
    if not all(selected.get(key) for key in ['INTERNXT_LOGIN_TESTS', 'INTERNXT_PW_TESTS']):
        parser.error('Missing Internxt test-account variables')
    environment = dict(os.environ, CRISP_INTERNXT_DOWNLOAD_LIVE='1',
                       CRISP_INTERNXT_TEST_EMAIL=selected['INTERNXT_LOGIN_TESTS'],
                       CRISP_INTERNXT_TEST_PASSWORD=selected['INTERNXT_PW_TESTS'])
    result = subprocess.run(['flutter', 'test', 'test/internxt_download_path_live_test.dart',
                             '--tags', 'live', '--run-skipped', '--reporter', 'expanded'],
                            cwd=Path(__file__).resolve().parents[1], env=environment)
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
