#!/usr/bin/env python3
"""Generate the original portable ASCII CPIO fixture with native libarchive.

This is optional fixture tooling, not an application dependency. The fixture
uses no CrispCloud serializer, and every payload is original test text.
"""

import ctypes as c
import hashlib
from pathlib import Path
import sys


def main():
    destination = (
        Path(sys.argv[1])
        if len(sys.argv) == 2
        else Path(__file__).resolve().parents[1]
        / "fixtures/archives/reference-odc.cpio"
    )
    if len(sys.argv) > 2:
        raise SystemExit("Usage: generate_cpio_odc_reference.py [output.cpio]")
    lib = c.CDLL("libarchive.so.13")
    lib.archive_version_string.restype = c.c_char_p
    lib.archive_write_new.restype = c.c_void_p
    lib.archive_entry_new.restype = c.c_void_p
    for name in (
        "archive_write_set_format_cpio_odc",
        "archive_write_close",
        "archive_write_free",
        "archive_entry_free",
    ):
        getattr(lib, name).argtypes = [c.c_void_p]
    lib.archive_write_set_bytes_per_block.argtypes = [c.c_void_p, c.c_int]
    lib.archive_write_open_filename.argtypes = [c.c_void_p, c.c_char_p]
    lib.archive_write_header.argtypes = [c.c_void_p, c.c_void_p]
    lib.archive_write_data.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_write_data.restype = c.c_ssize_t
    lib.archive_error_string.argtypes = [c.c_void_p]
    lib.archive_error_string.restype = c.c_char_p
    lib.archive_entry_set_pathname.argtypes = [c.c_void_p, c.c_char_p]
    lib.archive_entry_set_mode.argtypes = [c.c_void_p, c.c_uint]
    lib.archive_entry_set_nlink.argtypes = [c.c_void_p, c.c_uint]
    for field in ("size", "ino64", "uid", "gid"):
        getattr(lib, f"archive_entry_set_{field}").argtypes = [
            c.c_void_p,
            c.c_int64,
        ]
    lib.archive_entry_set_mtime.argtypes = [c.c_void_p, c.c_int64, c.c_long]

    writer = lib.archive_write_new()
    if not writer:
        raise RuntimeError("Could not create a libarchive writer")

    def checked(result):
        if result != 0:
            raise RuntimeError(lib.archive_error_string(writer))

    try:
        checked(lib.archive_write_set_format_cpio_odc(writer))
        # ODC has no per-member alignment. A one-byte physical block keeps
        # the fixture compact and also avoids unrelated trailing block padding.
        checked(lib.archive_write_set_bytes_per_block(writer, 1))
        destination.parent.mkdir(parents=True, exist_ok=True)
        checked(lib.archive_write_open_filename(writer, bytes(destination)))
        entries = (
            (b"docs", 0o040755, b""),
            (b"docs/hello.txt", 0o100640, b"Independent portable CPIO fixture\n"),
            (b"docs/odd", 0o100644, b"odd"),
        )
        for inode, (name, mode, data) in enumerate(entries, start=1):
            entry = lib.archive_entry_new()
            if not entry:
                raise RuntimeError("Could not create a libarchive entry")
            try:
                lib.archive_entry_set_pathname(entry, name)
                lib.archive_entry_set_mode(entry, mode)
                lib.archive_entry_set_size(entry, len(data))
                lib.archive_entry_set_ino64(entry, inode)
                lib.archive_entry_set_nlink(entry, 1)
                lib.archive_entry_set_uid(entry, 123)
                lib.archive_entry_set_gid(entry, 456)
                lib.archive_entry_set_mtime(entry, 1700000000, 0)
                checked(lib.archive_write_header(writer, entry))
                if data:
                    memory = c.create_string_buffer(data)
                    if lib.archive_write_data(writer, memory, len(data)) != len(data):
                        raise RuntimeError(lib.archive_error_string(writer))
            finally:
                lib.archive_entry_free(entry)
        checked(lib.archive_write_close(writer))
    finally:
        lib.archive_write_free(writer)

    raw = destination.read_bytes()
    assert raw[:6] == b"070707"
    print(lib.archive_version_string().decode())
    print(f"{len(raw)} bytes: {destination}")
    print(f"SHA-256 {hashlib.sha256(raw).hexdigest()}")


if __name__ == "__main__":
    main()
