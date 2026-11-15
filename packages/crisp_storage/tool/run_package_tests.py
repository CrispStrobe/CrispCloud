#!/usr/bin/env python3
"""Run storage tests in place; the removed libsmb2 install-name workaround is unnecessary."""
from pathlib import Path
import signal
import subprocess
import sys

PACKAGE_ROOT = Path(__file__).resolve().parent.parent


def status(returncode):
    return returncode if returncode >= 0 else 128 - returncode


def run_tests(arguments):
    return status(subprocess.run(['dart', 'test', *arguments],
                                 cwd=PACKAGE_ROOT, check=False).returncode)


def terminate(signum, _frame):
    raise SystemExit(128 + signum)


def main(arguments):
    if arguments in (['--help'], ['-h']):
        print('Usage: python3 tool/run_package_tests.py [--] [dart test arguments]')
        print(__doc__)
        return 0
    if arguments[:1] == ['--']:
        arguments = arguments[1:]
    signal.signal(signal.SIGTERM, terminate)
    return run_tests(arguments)


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
