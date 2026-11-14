#!/usr/bin/env python3
"""Run the pinned SDK with task-specific caches and temporary files."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
for name in ('pub-cache', 'tmp', 'cache', 'config', 'cargo', 'rustup', 'bin'):
    (ROOT / name).mkdir(exist_ok=True)
environment = os.environ.copy()
environment.update({
    'PUB_CACHE': str(ROOT / 'pub-cache'),
    'TMPDIR': str(ROOT / 'tmp'),
    'XDG_CACHE_HOME': str(ROOT / 'cache'),
    'XDG_CONFIG_HOME': str(ROOT / 'config'),
    'CARGO_HOME': str(ROOT / 'cargo'),
    'RUSTUP_HOME': str(ROOT / 'rustup'),
    'DART_DISABLE_ANALYTICS': 'true',
    'FLUTTER_SUPPRESS_ANALYTICS': 'true',
    'CI': 'true',
    'PATH': os.pathsep.join([str(ROOT / 'bin'), str(ROOT / 'cargo/bin'), str(ROOT / 'flutter/bin'), environment.get('PATH', '')]),
})
command = sys.argv[1:]
if not command:
    raise SystemExit('Usage: run.py flutter|dart|command ...')
if command[0] == 'flutter':
    command[0] = str(ROOT / 'flutter/bin/flutter')
elif command[0] == 'dart':
    command[0] = str(ROOT / 'flutter/bin/cache/dart-sdk/bin/dart')
raise SystemExit(subprocess.call(command, env=environment))
