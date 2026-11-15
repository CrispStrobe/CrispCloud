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
SQLITE_HOOK = b'    sqlite3:\n      source: system\n      name_windows: winsqlite3\n'
HOOK = b'hooks:\n  user_defines:\n' + SQLITE_HOOK


def _require_simple_values(text):
    # Even nested quoted/flow values can continue at a container's indentation,
    # making text that looks like a hooks key part of a different scalar.
    while re.match(rb'-[ \t]+', text):
        text = text[1:].lstrip(b' \t')
    special = (b"'", b'"', b'[', b'{', b'&', b'*', b'!', b'?')
    if not text.startswith(special):
        separator = re.search(rb':[ \t]+', text)
        if separator:
            text = text[separator.end():]
    if text.startswith((b"'", b'"')):
        if re.fullmatch(rb'''(?:'(?:[^']|'')*'|"(?:[^"\\]|\\.)*")(?:[ \t]+#.*)?[ \t]*''', text):
            return
    elif not text.startswith(special):
        return
    raise RuntimeError('Unsupported YAML value; refusing to merge SQLite hook')


def _block_mapping(tokens, indent, end_line):
    """Read only plain block-map keys; keep nested values opaque and unchanged."""
    entries = []
    seen = set()
    for line, depth, text in tokens:
        if depth > indent and entries:
            entries[-1][3].append((line, depth, text))
            continue
        match = re.fullmatch(rb'([A-Za-z_][A-Za-z0-9_-]*):(?:[ \t]+(.*))?', text)
        if depth != indent or match is None or match[1] in seen:
            raise RuntimeError('Unsupported or ambiguous YAML mapping; refusing to merge SQLite hook')
        seen.add(match[1])
        entries.append((match[1], line, match[2] or b'', []))
    return {
        key: (line, value, children, entries[index + 1][1] if index + 1 < len(entries) else end_line)
        for index, (key, line, value, children) in enumerate(entries)
    }


def _require_block_value(value):
    if value and not value.startswith(b'#'):
        raise RuntimeError('Only plain block mappings are supported when merging SQLite hooks')


def with_system_sqlite_hook(original):
    """Insert the test override without rewriting existing configuration.

    Containers use plain keys and two-space block indentation. Quoted values
    must fit on one line; aliases, anchors, tags and flow collections are not
    supported. Reject ambiguous shapes instead of guessing without a YAML parser.
    """
    if original and not original.endswith(b'\n'):
        # Adding a separator could change the value of a final block scalar.
        raise RuntimeError('A final newline is required to safely merge SQLite hooks')
    lines = original.splitlines(keepends=True)
    tokens = []
    for index, raw in enumerate(lines):
        line = raw.rstrip(b'\r\n')
        text = line.lstrip(b' ')
        if not text or text.startswith(b'#'):
            continue
        if text.startswith(b'\t'):
            raise RuntimeError('Unsupported YAML indentation; refusing to merge SQLite hook')
        _require_simple_values(text)
        tokens.append((index, len(line) - len(text), text))

    root = _block_mapping(tokens, 0, len(lines))
    hook = root.get(b'hooks')
    if hook is None:
        insert_at, addition = len(lines), HOOK
    else:
        _, value, children, hook_end = hook
        _require_block_value(value)
        defines = _block_mapping(children, 2, hook_end).get(b'user_defines')
        if defines is None:
            insert_at, addition = hook_end, b'  user_defines:\n' + SQLITE_HOOK
        else:
            _, value, children, defines_end = defines
            _require_block_value(value)
            packages = _block_mapping(children, 4, defines_end)
            if b'sqlite3' in packages:
                raise RuntimeError('Existing sqlite3 hook configuration; refusing to override it')
            for _, value, _, _ in packages.values():
                _require_block_value(value)
            insert_at, addition = defines_end, SQLITE_HOOK

    # Keep every original byte, including comments, other hook definitions and
    # scalar trailing newlines. Insertion occurs at the next sibling boundary.
    first_newline = re.search(rb'\r?\n', original)
    newline = first_newline[0] if first_newline else b'\n'
    before = b''.join(lines[:insert_at])
    return before + addition.replace(b'\n', newline) + b''.join(lines[insert_at:])


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
    modified = with_system_sqlite_hook(original)
    try:
        pubspec.write_bytes(modified)
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
