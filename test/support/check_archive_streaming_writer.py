"""Independent ZIP/TAR/7z readers for the standalone native writer checks.

Python zipfile/tarfile and system libarchive are validation dependencies only.
No external archive executable is used by the application.
"""
import ctypes
import ctypes.util
import hashlib
import json
from pathlib import Path
import struct
import sys
import tarfile
import zipfile


CHUNK = 256 * 1024


def check_bytes(chunks, expected):
    count = 0
    digest = hashlib.sha256()
    for chunk in chunks:
        count += len(chunk)
        if expected.get('zeros'):
            assert chunk.count(0) == len(chunk), 'nonzero content in generated zero stream'
        digest.update(chunk)
    assert count == expected['size'], (count, expected['size'])
    if 'sha256' in expected:
        assert digest.hexdigest() == expected['sha256']
    if expected.get('zeros'):
        print(f'  SHA-256 {digest.hexdigest()} ({count} zero bytes)')


def stream_chunks(stream):
    while chunk := stream.read(CHUNK):
        yield chunk


def check_zip(path, expected):
    with zipfile.ZipFile(path) as archive:
        assert len(archive.infolist()) == len(expected)
        for member in archive.infolist():
            want = expected[member.filename.rstrip('/')]
            assert member.is_dir() == want['directory']
            assert member.file_size == want['size']
            assert (member.external_attr >> 16) & 0xfff == want['mode']
            extras = member.extra
            while extras:
                tag, size = struct.unpack_from('<HH', extras)
                data, extras = extras[4:4 + size], extras[4 + size:]
                if tag == 0x5455:
                    assert data[0] & 1
                    assert struct.unpack_from('<I', data, 1)[0] == want['mtime']
                    break
            else:
                raise AssertionError('Missing UTC timestamp')
            if not member.is_dir():
                with archive.open(member) as stream:
                    check_bytes(stream_chunks(stream), want)


def check_tar(path, expected):
    with tarfile.open(path, 'r|*') as archive:
        seen = set()
        for member in archive:
            name = member.name.rstrip('/')
            want = expected[name]
            assert name not in seen
            seen.add(name)
            assert member.isdir() == want['directory']
            assert member.size == want['size']
            assert member.mode == want['mode']
            assert member.mtime == want['mtime']
            if member.isfile():
                with archive.extractfile(member) as stream:
                    check_bytes(stream_chunks(stream), want)
        assert seen == expected.keys()


def check_7z(path, expected):
    lib = ctypes.CDLL(ctypes.util.find_library('archive'))
    pointer = ctypes.c_void_p
    for name, args, result in [
        ('archive_read_new', [], pointer),
        ('archive_read_support_format_7zip', [pointer], ctypes.c_int),
        ('archive_read_open_filename', [pointer, ctypes.c_char_p, ctypes.c_size_t], ctypes.c_int),
        ('archive_read_next_header', [pointer, ctypes.POINTER(pointer)], ctypes.c_int),
        ('archive_read_data', [pointer, pointer, ctypes.c_size_t], ctypes.c_ssize_t),
        ('archive_read_free', [pointer], ctypes.c_int),
        ('archive_error_string', [pointer], ctypes.c_char_p),
        ('archive_entry_pathname_utf8', [pointer], ctypes.c_char_p),
        ('archive_entry_size', [pointer], ctypes.c_int64),
        ('archive_entry_mode', [pointer], ctypes.c_uint),
        ('archive_entry_mtime', [pointer], ctypes.c_int64),
    ]:
        function = getattr(lib, name)
        function.argtypes, function.restype = args, result
    reader = lib.archive_read_new()
    try:
        assert lib.archive_read_support_format_7zip(reader) == 0
        assert lib.archive_read_open_filename(reader, bytes(path), CHUNK) == 0
        entry = pointer()
        seen = set()
        buffer = ctypes.create_string_buffer(CHUNK)
        while True:
            status = lib.archive_read_next_header(reader, ctypes.byref(entry))
            if status == 1:
                break
            assert status == 0, lib.archive_error_string(reader)
            name = lib.archive_entry_pathname_utf8(entry).decode().rstrip('/')
            want = expected[name]
            assert name not in seen
            seen.add(name)
            mode = lib.archive_entry_mode(entry)
            assert bool(mode & 0x4000) == want['directory']
            assert mode & 0xfff == want['mode']
            assert lib.archive_entry_size(entry) == want['size']
            assert lib.archive_entry_mtime(entry) == want['mtime']

            def chunks():
                while True:
                    size = lib.archive_read_data(reader, buffer, CHUNK)
                    assert size >= 0, lib.archive_error_string(reader)
                    if not size:
                        return
                    yield buffer.raw[:size]

            if not want['directory']:
                check_bytes(chunks(), want)
        assert seen == expected.keys()
    finally:
        lib.archive_read_free(reader)


def main():
    directory = Path(sys.argv[1])
    cases = json.loads((directory / 'manifest.json').read_text())
    for case in cases:
        path = directory / case['archive']
        expected = {item['path']: item for item in case['members']}
        check = check_zip if path.suffix == '.zip' else check_7z if path.suffix == '.7z' else check_tar
        check(path, expected)
        print(f'PASS independent {path.name}: {sum(v["size"] for v in expected.values())} payload bytes')


if __name__ == '__main__':
    main()
