"""Original CAB dictionary fixture and independent libarchive readback.

Run from the repository root. Native libarchive is validation tooling only:
  python3 test/support/check_archive_cab.py
Regenerate the Python/zlib fixture (deterministic zlib 1.3.2 output):
  python3 test/support/check_archive_cab.py --generate
"""

import argparse
import ctypes
import ctypes.util
import hashlib
from pathlib import Path
import struct
import zlib


ROOT = Path(__file__).resolve().parents[1] / "fixtures" / "archives"


def checksum(data):
    result = 0
    for start in range(0, len(data), 4):
        block = data[start : start + 4]
        result ^= int.from_bytes(block, "little" if len(block) == 4 else "big")
    return result


def dictionary_contents():
    history = b"".join(hashlib.sha256(struct.pack("<L", i)).digest()
                       for i in range(1024))
    dependent = history[-2048:] * 2 + b"CAB history survives block boundaries.\n"
    return history, dependent


def generate():
    history, dependent = dictionary_contents()
    payload = bytearray()
    dictionary = b""
    for content in (history, dependent):
        encoder = zlib.compressobj(9, zlib.DEFLATED, -15, zdict=dictionary)
        compressed = encoder.compress(content) + encoder.flush()
        if dictionary:
            try:
                zlib.decompress(compressed, -15)
            except zlib.error:
                pass
            else:
                raise AssertionError("fixture must require the previous block")
            decoder = zlib.decompressobj(-15, zdict=dictionary)
            assert decoder.decompress(compressed) + decoder.flush() == content
        packed = b"CK" + compressed
        lengths = struct.pack("<HH", len(packed), len(content))
        payload.extend(struct.pack("<L", checksum(packed) ^ checksum(lengths)))
        payload.extend(lengths)
        payload.extend(packed)
        dictionary = (dictionary + content)[-32768:]
    files = bytearray()
    offset = 0
    for name, content in ((b"history.bin", history),
                          (b"uses-history.bin", dependent)):
        files.extend(struct.pack("<LLHHHH", len(content), offset, 0,
                                 (44 << 9) | (1 << 5) | 2, 0, 0x20))
        files.extend(name + b"\0")
        offset += len(content)
    data_offset = 44 + len(files)
    header = bytearray(36)
    header[:4] = b"MSCF"
    struct.pack_into("<L", header, 8, data_offset + len(payload))
    struct.pack_into("<L", header, 16, 44)
    struct.pack_into("<BBHH", header, 24, 3, 1, 1, 2)
    folder = struct.pack("<LHH", data_offset, 2, 1)
    (ROOT / "reference-zlib-history.cab").write_bytes(header + folder + files + payload)
    print("Generated with zlib", zlib.ZLIB_VERSION)


def native_read(path):
    lib = ctypes.CDLL(ctypes.util.find_library("archive"))
    lib.archive_read_new.restype = ctypes.c_void_p
    for name in ("archive_read_support_format_cab", "archive_read_support_filter_all",
                 "archive_read_free"):
        getattr(lib, name).argtypes = [ctypes.c_void_p]
        getattr(lib, name).restype = ctypes.c_int
    lib.archive_read_open_filename.argtypes = [ctypes.c_void_p, ctypes.c_char_p,
                                               ctypes.c_size_t]
    lib.archive_read_open_filename.restype = ctypes.c_int
    lib.archive_read_next_header.argtypes = [ctypes.c_void_p,
                                            ctypes.POINTER(ctypes.c_void_p)]
    lib.archive_read_next_header.restype = ctypes.c_int
    lib.archive_entry_pathname.argtypes = [ctypes.c_void_p]
    lib.archive_entry_pathname.restype = ctypes.c_char_p
    lib.archive_read_data.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]
    lib.archive_read_data.restype = ctypes.c_ssize_t
    lib.archive_error_string.argtypes = [ctypes.c_void_p]
    lib.archive_error_string.restype = ctypes.c_char_p
    reader = lib.archive_read_new()
    try:
        lib.archive_read_support_format_cab(reader)
        lib.archive_read_support_filter_all(reader)
        assert lib.archive_read_open_filename(reader, str(path).encode(), 32768) == 0
        entries = {}
        entry = ctypes.c_void_p()
        while True:
            status = lib.archive_read_next_header(reader, ctypes.byref(entry))
            if status == 1:
                return entries
            assert status == 0, lib.archive_error_string(reader)
            name = lib.archive_entry_pathname(entry).decode("utf-8").replace("\\", "/")
            data = bytearray()
            buffer = ctypes.create_string_buffer(32768)
            while True:
                size = lib.archive_read_data(reader, buffer, len(buffer))
                assert size >= 0, lib.archive_error_string(reader)
                if not size:
                    break
                data.extend(buffer.raw[:size])
            entries[name] = bytes(data)
    finally:
        lib.archive_read_free(reader)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate", action="store_true")
    args = parser.parse_args()
    if args.generate:
        generate()
    text1 = b"                          file 1 contents\n" + b"hello\n" * 3
    text2 = b"                          file 2 contents\n" + b"hello\n" * 6
    history, dependent = dictionary_contents()
    expected = {
        "reference-makecab-stored.cab": {"empty": b"", "dir1/file1": text1,
                                          "dir2/file2": text2},
        "reference-makecab-mszip.cab": {"empty": b"", "zero": bytes(33000),
                                         "dir1/file1": text1, "dir2/file2": text2},
        "reference-zlib-history.cab": {"history.bin": history,
                                       "uses-history.bin": dependent},
    }
    for name, contents in expected.items():
        path = ROOT / name
        assert native_read(path) == contents, name
        print(name, "PASS", len(path.read_bytes()), hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
