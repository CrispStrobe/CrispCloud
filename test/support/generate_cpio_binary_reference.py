#!/usr/bin/env python3
"""Generate/read back original binary CPIO fixtures using native libarchive.

Only 16-bit header words are byte-swapped for the opposite-endian fixture.
Both files are independently decoded by libarchive. No application writer or
third-party payloads are used. Run with --check-only to verify committed files.
"""
import argparse
import ctypes as c
import hashlib
from pathlib import Path
import struct
import tempfile

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures/archives"
ENTRIES = [
    (b"docs", 0o040755, b""),
    (b"docs/odd", 0o100640, b"odd"),
    (b"empty", 0o100600, b""),
    (b"payload.bin", 0o100755, bytes(i % 251 for i in range(65536 + 333))),
]


def library():
    lib = c.CDLL("libarchive.so.13")
    for name in ("archive_write_new", "archive_read_new", "archive_entry_new"):
        getattr(lib, name).restype = c.c_void_p
    for name in ("archive_write_set_format_cpio_bin", "archive_write_close", "archive_write_free", "archive_entry_free", "archive_read_support_format_cpio", "archive_read_close", "archive_read_free"):
        getattr(lib, name).argtypes = [c.c_void_p]
    lib.archive_version_string.restype = c.c_char_p
    lib.archive_error_string.argtypes = [c.c_void_p]
    lib.archive_error_string.restype = c.c_char_p
    lib.archive_write_set_bytes_per_block.argtypes = [c.c_void_p, c.c_int]
    lib.archive_write_open_filename.argtypes = [c.c_void_p, c.c_char_p]
    lib.archive_write_header.argtypes = [c.c_void_p, c.c_void_p]
    lib.archive_write_data.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_write_data.restype = c.c_ssize_t
    lib.archive_entry_set_pathname.argtypes = [c.c_void_p, c.c_char_p]
    lib.archive_entry_set_mode.argtypes = [c.c_void_p, c.c_uint]
    lib.archive_entry_set_nlink.argtypes = [c.c_void_p, c.c_uint]
    for field in ("size", "ino64", "uid", "gid"):
        getattr(lib, f"archive_entry_set_{field}").argtypes = [c.c_void_p, c.c_int64]
    lib.archive_entry_set_mtime.argtypes = [c.c_void_p, c.c_int64, c.c_long]
    lib.archive_read_open_memory.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_read_next_header.argtypes = [c.c_void_p, c.POINTER(c.c_void_p)]
    lib.archive_entry_pathname.argtypes = [c.c_void_p]
    lib.archive_entry_pathname.restype = c.c_char_p
    for field in ("size", "mtime"):
        getattr(lib, f"archive_entry_{field}").argtypes = [c.c_void_p]
        getattr(lib, f"archive_entry_{field}").restype = c.c_int64
    lib.archive_entry_mode.argtypes = [c.c_void_p]
    lib.archive_entry_mode.restype = c.c_uint
    lib.archive_read_data.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_read_data.restype = c.c_ssize_t
    return lib


def checked(lib, archive, result):
    if result != 0:
        raise RuntimeError(lib.archive_error_string(archive))


def generate(lib, path):
    archive = lib.archive_write_new()
    try:
        checked(lib, archive, lib.archive_write_set_format_cpio_bin(archive))
        checked(lib, archive, lib.archive_write_set_bytes_per_block(archive, 1))
        checked(lib, archive, lib.archive_write_open_filename(archive, bytes(path)))
        for inode, (name, mode, data) in enumerate(ENTRIES, 1):
            entry = lib.archive_entry_new()
            try:
                lib.archive_entry_set_pathname(entry, name)
                lib.archive_entry_set_mode(entry, mode)
                lib.archive_entry_set_nlink(entry, 1)
                lib.archive_entry_set_ino64(entry, inode)
                lib.archive_entry_set_uid(entry, 123)
                lib.archive_entry_set_gid(entry, 456)
                lib.archive_entry_set_mtime(entry, 1700000000, 0)
                lib.archive_entry_set_size(entry, len(data))
                checked(lib, archive, lib.archive_write_header(archive, entry))
                if data:
                    memory = c.create_string_buffer(data)
                    assert lib.archive_write_data(archive, memory, len(data)) == len(data)
            finally:
                lib.archive_entry_free(entry)
        checked(lib, archive, lib.archive_write_close(archive))
    finally:
        lib.archive_write_free(archive)
    return path.read_bytes()


def swap_headers(data):
    output = bytearray(data)
    order = "<" if data[:2] == b"\xc7\x71" else ">"
    at = 0
    while at < len(data):
        words = struct.unpack_from(order + "13H", data, at)
        assert words[0] == 0o70707
        name_size, size = words[10], (words[11] << 16) + words[12]
        name = data[at + 26:at + 26 + name_size - 1]
        for position in range(at, at + 26, 2):
            output[position:position + 2] = data[position:position + 2][::-1]
        at = (at + 26 + name_size + 1) // 2 * 2
        at = (at + size + 1) // 2 * 2
        if name == b"TRAILER!!!":
            assert size == 0 and not any(data[at:])
            break
    return bytes(output)


def verify(lib, data):
    archive = lib.archive_read_new()
    memory = c.create_string_buffer(data)
    try:
        checked(lib, archive, lib.archive_read_support_format_cpio(archive))
        checked(lib, archive, lib.archive_read_open_memory(archive, memory, len(data)))
        entry = c.c_void_p()
        for name, mode, expected in ENTRIES:
            checked(lib, archive, lib.archive_read_next_header(archive, c.byref(entry)))
            assert lib.archive_entry_pathname(entry) == name
            assert lib.archive_entry_mode(entry) == mode
            assert lib.archive_entry_mtime(entry) == 1700000000
            assert lib.archive_entry_size(entry) == len(expected)
            output = c.create_string_buffer(len(expected) + 1)
            count = lib.archive_read_data(archive, output, len(expected) + 1)
            assert count == len(expected) and output.raw[:count] == expected
        assert lib.archive_read_next_header(archive, c.byref(entry)) == 1
        checked(lib, archive, lib.archive_read_close(archive))
    finally:
        lib.archive_read_free(archive)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    lib = library()
    with tempfile.TemporaryDirectory(prefix="cpio-binary-reference-") as temporary:
        native = generate(lib, Path(temporary) / "native.cpio")
    swapped = swap_headers(native)
    little, big = (native, swapped) if native[:2] == b"\xc7\x71" else (swapped, native)
    print(lib.archive_version_string().decode())
    for suffix, data in (("le", little), ("be", big)):
        path = FIXTURES / f"reference-binary-{suffix}.cpio"
        verify(lib, data)
        if args.check_only:
            assert path.read_bytes() == data
        else:
            path.write_bytes(data)
        print(f"{path.name}: {len(data)} bytes, SHA-256 {hashlib.sha256(data).hexdigest()}, exact native readback passed")


if __name__ == "__main__":
    main()
