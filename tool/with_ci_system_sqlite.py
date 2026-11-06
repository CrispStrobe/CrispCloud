#!/usr/bin/env python3
"""Run a trusted CI test command with distro/OS SQLite, restoring pubspec.

sqlite3 3.3.3 documents this hook in doc/hook.md (System-provided SQLite).
This is deliberately opt-in for tests; release builds keep the verified bundle.
"""
import ctypes
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
HOOK = b'\nhooks:\n  user_defines:\n    sqlite3:\n      source: system\n      name_windows: winsqlite3\n'


def probe_system_sqlite():
    library = 'winsqlite3.dll' if sys.platform == 'win32' else 'libsqlite3.so'
    sqlite = ctypes.CDLL(library)
    sqlite.sqlite3_libversion.restype = ctypes.c_char_p
    sqlite.sqlite3_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    sqlite.sqlite3_close.argtypes = [ctypes.c_void_p]
    sqlite.sqlite3_exec.argtypes = [ctypes.c_void_p, ctypes.c_char_p,
                                  ctypes.c_void_p, ctypes.c_void_p,
                                  ctypes.POINTER(ctypes.c_char_p)]
    sqlite.sqlite3_free.argtypes = [ctypes.c_void_p]
    database = ctypes.c_void_p()
    if sqlite.sqlite3_open(b':memory:', ctypes.byref(database)) != 0:
        if database.value:
            sqlite.sqlite3_close(database)
        raise RuntimeError('System SQLite could not open an in-memory database')

    def execute(sql):
        error = ctypes.c_char_p()
        status = sqlite.sqlite3_exec(database, sql, None, None, ctypes.byref(error))
        message = error.value.decode('utf-8', errors='replace') if error.value else ''
        if error:
            sqlite.sqlite3_free(error)
        return status, message

    try:
        # Current Drift schema uses ordinary tables, transactions and references.
        # A deliberate FK violation proves enforcement rather than just parsing.
        status, error = execute(b'PRAGMA foreign_keys=ON; CREATE TABLE parent(id INTEGER PRIMARY KEY); '
                                b'CREATE TABLE child(id INTEGER REFERENCES parent(id)); '
                                b'BEGIN; INSERT INTO parent VALUES(1); INSERT INTO child VALUES(1); COMMIT;')
        if status:
            raise RuntimeError(f'System SQLite schema/transaction probe failed: {error}')
        status, _ = execute(b'INSERT INTO child VALUES(99);')
        if status != 19:  # SQLITE_CONSTRAINT
            raise RuntimeError('System SQLite did not enforce foreign keys')
        fts5, _ = execute(b'CREATE VIRTUAL TABLE search_probe USING fts5(content);')
        print(f'CI SQLite: {library}, version {sqlite.sqlite3_libversion().decode()}, '
              f'foreign keys/transactions verified; optional FTS5={fts5 == 0}', flush=True)
    finally:
        sqlite.sqlite3_close(database)


def run_with_system_sqlite(command, pubspec=ROOT / 'pubspec.yaml'):
    original = pubspec.read_bytes()
    if re.search(rb'^hooks\s*:', original, flags=re.MULTILINE):
        raise RuntimeError('Existing hooks configuration needs explicit merging; refusing to overwrite it')
    try:
        pubspec.write_bytes(original.rstrip(b'\r\n') + b'\n' + HOOK)
        # On Windows Flutter is a .bat entrypoint. Commands here are trusted CI
        # arguments, never filenames or data supplied by an external user.
        return subprocess.run(command, cwd=pubspec.parent, shell=os.name == 'nt', check=False).returncode
    finally:
        pubspec.write_bytes(original)


def main():
    command = sys.argv[1:]
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        raise SystemExit('Usage: with_ci_system_sqlite.py [--] flutter test ...')
    if sys.platform not in ('linux', 'win32'):
        return subprocess.run(command, cwd=ROOT, check=False).returncode
    # Make termination unwind the finally block restoring pubspec as well.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    probe_system_sqlite()
    return run_with_system_sqlite(command)


if __name__ == '__main__':
    sys.exit(main())
