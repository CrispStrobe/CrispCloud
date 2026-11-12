"""Independently read original Dart CPIO writer output with native libarchive.

Also inspect the physical headers with Python struct to check profile, raw
legacy device IDs, inode/link fields, exact padding and trailer boundaries.
The application never imports this checker or native library.
"""
import ctypes as c
import hashlib
import json
import locale
from pathlib import Path
import struct
import sys


def native_reader():
    lib = c.CDLL('libarchive.so.13')
    lib.archive_version_string.restype = c.c_char_p
    lib.archive_read_new.restype = c.c_void_p
    for name in ('archive_read_support_format_cpio', 'archive_read_free'):
        getattr(lib, name).argtypes = [c.c_void_p]
    lib.archive_read_open_memory.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_read_next_header.argtypes = [c.c_void_p, c.POINTER(c.c_void_p)]
    lib.archive_read_data.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_read_data.restype = c.c_ssize_t
    lib.archive_error_string.argtypes = [c.c_void_p]
    lib.archive_error_string.restype = c.c_char_p
    lib.archive_entry_pathname_utf8.argtypes = [c.c_void_p]
    lib.archive_entry_pathname_utf8.restype = c.c_char_p
    for name in ('size', 'uid', 'gid', 'mtime', 'ino64', 'dev', 'rdev'):
        fn = getattr(lib, 'archive_entry_' + name)
        fn.argtypes = [c.c_void_p]
        fn.restype = c.c_int64
    for name in ('mode', 'nlink'):
        fn = getattr(lib, 'archive_entry_' + name)
        fn.argtypes = [c.c_void_p]
        fn.restype = c.c_uint

    def read(raw):
        memory = c.create_string_buffer(raw)
        reader = lib.archive_read_new()
        entry = c.c_void_p()
        result = []
        try:
            assert lib.archive_read_support_format_cpio(reader) == 0
            assert lib.archive_read_open_memory(reader, memory, len(raw)) == 0
            while True:
                status = lib.archive_read_next_header(reader, c.byref(entry))
                if status == 1:
                    break
                assert status == 0, lib.archive_error_string(reader)
                row = {
                    'path': lib.archive_entry_pathname_utf8(entry).decode('utf-8').rstrip('/'),
                    **{key: getattr(lib, 'archive_entry_' + fn)(entry) for key, fn in (
                        ('size', 'size'), ('mode', 'mode'), ('uid', 'uid'), ('gid', 'gid'),
                        ('mtime', 'mtime'), ('dev', 'dev'), ('rdev', 'rdev'),
                        ('ino', 'ino64'), ('nlink', 'nlink'),
                    )},
                }
                digest = hashlib.sha256()
                count = 0
                buffer = c.create_string_buffer(32768)
                while True:
                    size = lib.archive_read_data(reader, buffer, len(buffer))
                    assert size >= 0, lib.archive_error_string(reader)
                    if size == 0:
                        break
                    digest.update(buffer.raw[:size])
                    count += size
                assert count == row['size'], (row['path'], count, row['size'])
                row['sha256'] = digest.hexdigest()
                result.append(row)
            return result
        finally:
            lib.archive_read_free(reader)

    return lib.archive_version_string().decode(), read


def headers(raw, profile):
    records = []
    at = 0
    while True:
        if profile == '070707':
            assert raw[at:at + 6] == b'070707'
            fields = []
            start = at + 6
            for width in (6, 6, 6, 6, 6, 6, 6, 11, 6, 11):
                text = raw[start:start + width]
                assert len(text) == width and all(48 <= b <= 55 for b in text)
                fields.append(int(text, 8))
                start += width
            alignment = 1
        else:
            endian = '<' if profile == 'binary-le' else '>'
            words = struct.unpack_from(endian + '13H', raw, at)
            assert words[0] == 0o70707
            fields = [*words[1:8], words[8] * 65536 + words[9],
                      words[10], words[11] * 65536 + words[12]]
            start = at + 26
            alignment = 2
        dev, ino, mode, uid, gid, nlink, rdev, mtime, namesize, size = fields
        name = raw[start:start + namesize]
        assert name.endswith(b'\0') and b'\0' not in name[:-1]
        start += namesize
        data_start = (start + alignment - 1) // alignment * alignment
        assert not any(raw[start:data_start])
        end = data_start + size
        at = (end + alignment - 1) // alignment * alignment
        assert at <= len(raw) and not any(raw[end:at])
        row = {'path': name[:-1].decode('utf-8').rstrip('/'),
               'dev': dev, 'ino': ino, 'mode': mode, 'uid': uid, 'gid': gid,
               'nlink': nlink, 'rdev': rdev, 'mtime': mtime, 'size': size,
               'sha256': hashlib.sha256(raw[data_start:end]).hexdigest()}
        if name == b'TRAILER!!!\0':
            assert size == 0 and len(raw) - at <= 65536 and not any(raw[at:])
            return records, fields, len(raw) - at
        records.append(row)


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Supply the directory emitted by emit_archive_cpio_profiles.dart.')
    locale.setlocale(locale.LC_ALL, '')
    directory = Path(sys.argv[1])
    version, read = native_reader()
    print(version)
    cases = json.loads((directory / 'manifest.json').read_text())
    for case in cases:
        raw = (directory / case['file']).read_bytes()
        actual = read(raw)
        physical, trailer, padding = headers(raw, case['profile'])
        assert actual == physical, (case['file'], actual, physical)
        if 'source' in case:
            source = (directory / case['source']).read_bytes()
            expected = read(source)
            assert headers(raw, case['profile']) == headers(source, case['profile'])
            if case.get('identicalBytes'):
                assert raw == source
        else:
            expected = case['entries']
        assert actual == expected, (case['file'], actual, expected)
        print(f"PASS {case['file']}: {len(actual)} members, native data/metadata and exact framing")
    print(f'All {len(cases)} independent CPIO profile checks passed.')


if __name__ == '__main__':
    main()
