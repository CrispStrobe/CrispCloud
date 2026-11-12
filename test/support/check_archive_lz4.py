#!/usr/bin/env python3
"""Generate original LZ4 fixtures or independently check a Dart writer result.

Optional validation tooling only: the application never calls this script or
loads liblz4. The fixture payloads are deterministic original test data.
"""

import ctypes as c
import ctypes.util
import hashlib
from pathlib import Path
import sys


class FrameInfo(c.Structure):
    _fields_ = [
        ("block_size", c.c_uint),
        ("block_mode", c.c_uint),
        ("content_checksum", c.c_uint),
        ("frame_type", c.c_uint),
        ("content_size", c.c_ulonglong),
        ("dictionary_id", c.c_uint),
        ("block_checksum", c.c_uint),
    ]


class Preferences(c.Structure):
    _fields_ = [
        ("frame_info", FrameInfo),
        ("compression_level", c.c_int),
        ("auto_flush", c.c_uint),
        ("favor_decode_speed", c.c_uint),
        ("reserved", c.c_uint * 3),
    ]


class ReferenceLz4:
    def __init__(self):
        name = ctypes.util.find_library("lz4")
        # Flutter's test process can remove the loader search environment that
        # ctypes uses on macOS. Resolve the standard Homebrew locations directly.
        if name is None and sys.platform == "darwin":
            name = next((str(p) for p in (
                Path("/opt/homebrew/lib/liblz4.dylib"),
                Path("/usr/local/lib/liblz4.dylib"),
            ) if p.is_file()), None)
        if name is None:
            raise RuntimeError("Independent verification requires liblz4")
        self.lib = lib = c.CDLL(name)
        lib.LZ4_versionString.restype = c.c_char_p
        lib.LZ4F_isError.argtypes = [c.c_size_t]
        lib.LZ4F_isError.restype = c.c_uint
        lib.LZ4F_getErrorName.argtypes = [c.c_size_t]
        lib.LZ4F_getErrorName.restype = c.c_char_p
        lib.LZ4F_compressFrameBound.argtypes = [c.c_size_t, c.POINTER(Preferences)]
        lib.LZ4F_compressFrameBound.restype = c.c_size_t
        lib.LZ4F_compressFrame.argtypes = [
            c.c_void_p, c.c_size_t, c.c_void_p, c.c_size_t,
            c.POINTER(Preferences),
        ]
        lib.LZ4F_compressFrame.restype = c.c_size_t
        lib.LZ4F_createDecompressionContext.argtypes = [
            c.POINTER(c.c_void_p), c.c_uint,
        ]
        lib.LZ4F_createDecompressionContext.restype = c.c_size_t
        lib.LZ4F_freeDecompressionContext.argtypes = [c.c_void_p]
        lib.LZ4F_freeDecompressionContext.restype = c.c_size_t
        lib.LZ4F_decompress.argtypes = [
            c.c_void_p, c.c_void_p, c.POINTER(c.c_size_t),
            c.c_void_p, c.POINTER(c.c_size_t), c.c_void_p,
        ]
        lib.LZ4F_decompress.restype = c.c_size_t

    def checked(self, result):
        if self.lib.LZ4F_isError(result):
            raise RuntimeError(self.lib.LZ4F_getErrorName(result).decode())
        return result

    def compress(self, payload, *, linked=False, checksums=True, sized=True):
        prefs = Preferences()
        prefs.frame_info.block_size = 4  # 64 KiB, exposing linked-block use.
        prefs.frame_info.block_mode = 0 if linked else 1
        prefs.frame_info.content_checksum = int(checksums)
        prefs.frame_info.block_checksum = int(checksums)
        prefs.frame_info.content_size = len(payload) if sized else 0
        capacity = self.checked(self.lib.LZ4F_compressFrameBound(
            len(payload), c.byref(prefs)))
        output = c.create_string_buffer(capacity)
        source = c.create_string_buffer(payload)
        size = self.checked(self.lib.LZ4F_compressFrame(
            output, capacity, source, len(payload), c.byref(prefs)))
        packed = output.raw[:size]
        assert self.decode(packed) == payload
        return packed

    def decode(self, packed):
        context = c.c_void_p()
        self.checked(self.lib.LZ4F_createDecompressionContext(
            c.byref(context), 100))
        source = c.create_string_buffer(packed)
        at = 0
        result = bytearray()
        try:
            while True:
                output = c.create_string_buffer(1024 * 1024)
                output_size = c.c_size_t(len(output))
                input_size = c.c_size_t(len(packed) - at)
                hint = self.checked(self.lib.LZ4F_decompress(
                    context, output, c.byref(output_size),
                    c.byref(source, at), c.byref(input_size), None))
                at += input_size.value
                result.extend(output.raw[:output_size.value])
                if len(result) > 64 * 1024 * 1024:
                    raise RuntimeError("Reference decode exceeds the test limit")
                if hint == 0:
                    if at != len(packed):
                        raise RuntimeError("Reference decode left trailing data")
                    return bytes(result)
                if input_size.value == output_size.value == 0:
                    raise RuntimeError("Reference decode made no progress")
        finally:
            self.checked(self.lib.LZ4F_freeDecompressionContext(context))


def random_data(size):
    value = 0x13579BDF
    result = bytearray()
    for _ in range(size):
        value = (value * 1664525 + 1013904223) & 0xFFFFFFFF
        result.append(value >> 24)
    return bytes(result)


def main():
    reference = ReferenceLz4()
    if len(sys.argv) == 4 and sys.argv[1] == "verify":
        packed, expected = (Path(name).read_bytes() for name in sys.argv[2:])
        actual = reference.decode(packed)
        if actual != expected:
            raise RuntimeError("Independent LZ4 output differs from its source")
        print(f"liblz4 {reference.lib.LZ4_versionString().decode()}: "
              f"verified {len(packed)} compressed / {len(actual)} decoded bytes")
        return
    if len(sys.argv) != 2 or sys.argv[1] != "generate":
        raise SystemExit("Usage: check_archive_lz4.py generate | verify frame source")
    destination = Path(__file__).resolve().parents[1] / "fixtures/archives"
    destination.mkdir(parents=True, exist_ok=True)
    cases = [
        ("linked", random_data(8192) * 40 + b"tail", {"linked": True}),
        ("independent", b"Independent LZ4 reference fixture\n" * 10000, {}),
        ("unchecked", bytes(range(256)) * 40 + b"end",
         {"checksums": False, "sized": False}),
        ("stored", random_data(8192), {}),
        ("empty", b"", {}),
    ]
    print(f"liblz4 {reference.lib.LZ4_versionString().decode()}")
    for name, payload, options in cases:
        packed = reference.compress(payload, **options)
        path = destination / f"lz4-reference-{name}.lz4"
        path.write_bytes(packed)
        print(f"{path.name}: {len(packed)} bytes; "
              f"SHA-256 {hashlib.sha256(packed).hexdigest()}")


if __name__ == "__main__":
    main()
