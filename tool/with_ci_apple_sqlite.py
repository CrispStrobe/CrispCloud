#!/usr/bin/env python3
"""Run an Apple build with exact pinned SQLite assets and restore its manifest.

sqlite3 3.3.3's local-precompiled source is named `test-sqlite3` upstream.
It reads the same release libraries and verifies the same upstream hashes;
it does not change SQLite or substitute the system library. This avoids
network downloads inside Xcode and unstable hook cache directory names.
"""
from pathlib import Path
import hashlib
import re
import subprocess
import sys

from with_ci_system_sqlite import SQLITE_HOOK, with_system_sqlite_hook

ROOT = Path(__file__).resolve().parent.parent
ASSETS = {
    'libsqlite3.arm64.ios.dylib': 'd14af900727328a6ae064217003618a7a860c79ac5bb1cab13334e249e7a4b6d',
    'libsqlite3.arm64.macos.dylib': '71074bec684ce243031c34ba16314dcfc39efefa77e72cc95f19b446b224254f',
    'libsqlite3.x64.macos.dylib': '602566eb722094e71f44630af8acc9ecded46b146d4de05b1c1a34f4fc5d0fda',
}
DIRECTORY = '.dart_tool/apple-sqlite-assets'
LOCAL_HOOK = (
    b'    sqlite3:\n'
    b'      source: test-sqlite3\n'
    b'      directory: .dart_tool/apple-sqlite-assets/\n'
)


def run_with_apple_sqlite(command, root=ROOT):
    if not command:
        raise ValueError('An Apple build or test command is required')
    lock = (root / 'pubspec.lock').read_text()
    entry = re.search(r'^  sqlite3:\n(?P<body>(?:    .*\n)+)', lock, re.MULTILINE)
    if entry is None or not re.search(r'^    version: "3\.3\.3"$', entry['body'], re.MULTILINE):
        raise RuntimeError('Apple SQLite assets require the reviewed sqlite3 3.3.3 lock entry')
    for name, expected in ASSETS.items():
        path = root / DIRECTORY / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise RuntimeError(f'Missing or changed pinned Apple SQLite asset: {name}')
    pubspec = root / 'pubspec.yaml'
    original = pubspec.read_bytes()
    modified = with_system_sqlite_hook(original)
    newline = b'\r\n' if b'\r\n' in original else b'\n'
    old = SQLITE_HOOK.replace(b'\n', newline)
    if modified.count(old) != 1:
        raise RuntimeError('Cannot identify the inserted SQLite override')
    modified = modified.replace(old, LOCAL_HOOK.replace(b'\n', newline), 1)
    try:
        pubspec.write_bytes(modified)
        return subprocess.run(command, cwd=root, check=False).returncode
    finally:
        pubspec.write_bytes(original)


if __name__ == '__main__':
    args = sys.argv[1:]
    if args[:1] == ['--']:
        args = args[1:]
    raise SystemExit(run_with_apple_sqlite(args))
