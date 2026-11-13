"""Independent libarchive ISO oracle for the streamed rewrite probe.

The application has no dependency on Python or system libarchive.
"""
import ctypes
import ctypes.util
import hashlib
import json
from pathlib import Path
import sys


def main():
    directory = Path(sys.argv[1])
    path = directory / 'rewritten.iso'
    expected = {item['path']: item for item in json.loads((directory / 'manifest.json').read_text())['members']}
    lib = ctypes.CDLL(ctypes.util.find_library('archive'))
    pointer = ctypes.c_void_p
    for name, args, result in [
        ('archive_read_new', [], pointer),
        ('archive_read_support_format_iso9660', [pointer], ctypes.c_int),
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
        assert lib.archive_read_support_format_iso9660(reader) == 0
        assert lib.archive_read_open_filename(reader, bytes(path), 256 * 1024) == 0
        entry = pointer()
        seen = set()
        buffer = ctypes.create_string_buffer(256 * 1024)
        total = 0
        while True:
            status = lib.archive_read_next_header(reader, ctypes.byref(entry))
            if status == 1:
                break
            assert status == 0, lib.archive_error_string(reader)
            name = lib.archive_entry_pathname_utf8(entry).decode().rstrip('/')
            mode = lib.archive_entry_mode(entry)
            if name in ('', '.') and mode & 0x4000:
                continue
            want = expected[name]
            assert name not in seen
            seen.add(name)
            assert bool(mode & 0x4000) == want['directory']
            assert mode & 0xfff == want['mode']
            assert lib.archive_entry_mtime(entry) == want['mtime']
            if want['directory']:
                continue
            assert lib.archive_entry_size(entry) == want['size']
            count = 0
            digest = hashlib.sha256()
            text = bytearray()
            while True:
                size = lib.archive_read_data(reader, buffer, len(buffer))
                assert size >= 0, lib.archive_error_string(reader)
                if not size:
                    break
                chunk = buffer.raw[:size]
                count += size
                digest.update(chunk)
                if want.get('zeros'):
                    assert chunk.count(0) == size, 'nonzero byte in large member'
                if 'text' in want:
                    text.extend(chunk)
            assert count == want['size']
            if 'text' in want:
                assert text.decode() == want['text']
            total += count
            print(f'PASS libarchive ISO {name}: {count} bytes, SHA-256 {digest.hexdigest()}')
        assert seen == expected.keys(), (seen, expected.keys())
        stat = path.stat()
        print(json.dumps({'independentIsoPayloadBytes': total, 'containerBytes': stat.st_size,
                          'allocatedBytes': stat.st_blocks * 512 if hasattr(stat, 'st_blocks') else None}))
    finally:
        lib.archive_read_free(reader)


if __name__ == '__main__':
    main()
