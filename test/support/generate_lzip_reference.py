#!/usr/bin/env python3
"""Original Lzip fixtures from libarchive, independently decoded by liblzma."""

import ctypes as c
import ctypes.util
import hashlib
import lzma
from pathlib import Path
import struct
import zlib


def random_data(size):
    value = 0x13579BDF
    result = bytearray()
    for _ in range(size):
        value = (value * 1664525 + 1013904223) & 0xFFFFFFFF
        result.append(value >> 24)
    return bytes(result)


def compress(payload):
    lib = c.CDLL(ctypes.util.find_library("archive"))
    lib.archive_write_new.restype = c.c_void_p
    lib.archive_entry_new.restype = c.c_void_p
    for function in [
        "archive_write_set_format_raw", "archive_write_add_filter_lzip",
        "archive_write_close", "archive_write_free", "archive_entry_free",
    ]:
        getattr(lib, function).argtypes = [c.c_void_p]
    lib.archive_error_string.argtypes = [c.c_void_p]
    lib.archive_error_string.restype = c.c_char_p
    lib.archive_write_set_bytes_per_block.argtypes = [c.c_void_p, c.c_int]
    lib.archive_write_open_memory.argtypes = [
        c.c_void_p, c.c_void_p, c.c_size_t, c.POINTER(c.c_size_t),
    ]
    lib.archive_entry_set_pathname.argtypes = [c.c_void_p, c.c_char_p]
    lib.archive_entry_set_mode.argtypes = [c.c_void_p, c.c_uint]
    lib.archive_entry_set_size.argtypes = [c.c_void_p, c.c_longlong]
    lib.archive_write_header.argtypes = [c.c_void_p, c.c_void_p]
    lib.archive_write_data.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_write_data.restype = c.c_ssize_t
    writer = lib.archive_write_new()
    entry = lib.archive_entry_new()
    output = c.create_string_buffer(len(payload) * 2 + 65536)
    used = c.c_size_t()

    def checked(result):
        if result != 0:
            raise RuntimeError(lib.archive_error_string(writer))

    try:
        checked(lib.archive_write_set_format_raw(writer))
        checked(lib.archive_write_add_filter_lzip(writer))
        checked(lib.archive_write_set_bytes_per_block(writer, 1))
        checked(lib.archive_write_open_memory(writer, output, len(output), c.byref(used)))
        lib.archive_entry_set_pathname(entry, b"original-test-data")
        lib.archive_entry_set_mode(entry, 0o100644)
        lib.archive_entry_set_size(entry, len(payload))
        checked(lib.archive_write_header(writer, entry))
        source = c.create_string_buffer(payload)
        if payload and lib.archive_write_data(writer, source, len(payload)) != len(payload):
            raise RuntimeError(lib.archive_error_string(writer))
        checked(lib.archive_write_close(writer))
    finally:
        lib.archive_entry_free(entry)
        lib.archive_write_free(writer)
    return output.raw[:used.value]


def verify(packed, expected):
    assert packed[:5] == b"LZIP\x01"
    code = packed[5]
    base = 1 << (code & 31)
    dictionary = base - (base // 16) * (code >> 5)
    crc, decoded_size, member_size = struct.unpack("<IQQ", packed[-20:])
    decoder = lzma.LZMADecompressor(format=lzma.FORMAT_RAW, filters=[dict(
        id=lzma.FILTER_LZMA1, dict_size=dictionary, lc=3, lp=0, pb=2,
    )])
    actual = decoder.decompress(packed[6:-20])
    assert decoder.eof and not decoder.unused_data
    assert actual == expected
    assert decoded_size == len(actual) and member_size == len(packed)
    assert zlib.crc32(actual) == crc


def main():
    destination = Path(__file__).resolve().parents[1] / "fixtures/archives"
    destination.mkdir(parents=True, exist_ok=True)
    for name, payload in [
        ("default", b"Independent Lzip reference fixture\n" * 5000),
        ("distance", random_data(8192) * 4),
        ("tiny", b"x"),
        ("empty", b""),
    ]:
        packed = compress(payload)
        verify(packed, payload)
        path = destination / f"lzip-reference-{name}.lz"
        path.write_bytes(packed)
        print(f"{path.name}: {len(packed)} bytes; "
              f"SHA-256 {hashlib.sha256(packed).hexdigest()}")


if __name__ == "__main__":
    main()
