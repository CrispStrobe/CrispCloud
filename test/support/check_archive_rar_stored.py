"""Independent libarchive oracle for CrispCloud's RAR5 Store implementation.

libarchive is a verification dependency, never an application runtime packer.
All bytes are consumed; no extracted path is written to the filesystem.
"""

import ctypes
import ctypes.util
import hashlib
import json
from pathlib import Path
import stat
import struct
import sys
import zlib


CHUNK = 256 * 1024


def vint(data, offset):
    value = 0
    for count in range(10):
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << (count * 7)
        if not byte & 128:
            return value, offset
    raise AssertionError("Overlong RAR integer")


def exact_metadata(path, expected):
    """Independent public-spec parser for metadata libarchive 3.7.4 rounds.

    It skips payloads positionally; libarchive independently consumes every
    payload below. No app implementation or RAR compression engine is imported.
    """
    seen = set()
    with path.open("rb") as source:
        assert source.read(8) == b"Rar!\x1a\x07\x01\x00"
        while True:
            crc_bytes = source.read(4)
            assert len(crc_bytes) == 4
            size_bytes = bytearray()
            for _ in range(3):
                item = source.read(1)
                assert item
                size_bytes.extend(item)
                if not item[0] & 128:
                    break
            size, _ = vint(size_bytes, 0)
            assert 0 < size <= 0x1fffff
            body = source.read(size)
            assert len(body) == size
            assert zlib.crc32(size_bytes + body) == struct.unpack("<I", crc_bytes)[0]
            kind, position = vint(body, 0)
            flags, position = vint(body, position)
            extra_size = packed_size = 0
            if flags & 1:
                extra_size, position = vint(body, position)
            if flags & 2:
                packed_size, position = vint(body, position)
            if kind == 5:
                assert not source.read(1)
                break
            if kind == 2:
                file_flags, position = vint(body, position)
                unpacked, position = vint(body, position)
                attributes, position = vint(body, position)
                mtime = None
                if file_flags & 2:
                    mtime = struct.unpack_from("<I", body, position)[0] * 1_000_000
                    position += 4
                if file_flags & 4:
                    position += 4
                compression, position = vint(body, position)
                host, position = vint(body, position)
                length, position = vint(body, position)
                name = body[position:position + length].decode("utf-8").rstrip("/")
                position += length
                assert position == len(body) - extra_size
                assert compression & 0x3ff == 0 and host in (0, 1)
                assert unpacked == packed_size
                assert name not in seen and name in expected
                seen.add(name)
                want = expected[name]
                assert unpacked == want["size"]
                assert bool(file_flags & 1) == want["directory"]
                raw_time = None
                while position < len(body):
                    length, position = vint(body, position)
                    stop = position + length
                    extra_kind, position = vint(body, position)
                    assert extra_kind == 3
                    time_flags, position = vint(body, position)
                    raw_time = {"flags": time_flags}
                    time_values = {}
                    time_nanos = {}
                    for label, flag in (("mtime", 2), ("ctime", 4), ("atime", 8)):
                        if time_flags & flag:
                            code = "<I" if time_flags & 1 else "<Q"
                            value = struct.unpack_from(code, body, position)[0]
                            position += struct.calcsize(code)
                            raw_time[label] = str(value)
                            time_values[label] = value
                    if time_flags & 1 and time_flags & 16:
                        for label, flag in (("mtime", 2), ("ctime", 4), ("atime", 8)):
                            if time_flags & flag:
                                value = struct.unpack_from("<I", body, position)[0]
                                position += 4
                                assert value < 1_000_000_000
                                raw_time[label + "Ns"] = value
                                time_nanos[label] = value
                    assert position == stop
                    if "mtime" in time_values:
                        mtime = (time_values["mtime"] * 1_000_000 + time_nanos.get("mtime", 0) // 1000
                                 if time_flags & 1 else (time_values["mtime"] - 116444736000000000) // 10)
                assert mtime == want.get("mtimeMicros"), (name, mtime, want.get("mtimeMicros"))
                if "rar5Times" in want:
                    assert raw_time == want["rar5Times"], (name, raw_time, want["rar5Times"])
            source.seek(packed_size, 1)
    assert seen == expected.keys()


def check(path, expected):
    exact_metadata(path, expected)
    library = ctypes.util.find_library("archive")
    if not library:
        raise RuntimeError("The independent RAR oracle requires libarchive.")
    lib = ctypes.CDLL(library)
    pointer = ctypes.c_void_p
    signatures = [
        ("archive_read_new", [], pointer),
        ("archive_read_support_format_rar5", [pointer], ctypes.c_int),
        ("archive_read_open_filename", [pointer, ctypes.c_char_p, ctypes.c_size_t], ctypes.c_int),
        ("archive_read_next_header", [pointer, ctypes.POINTER(pointer)], ctypes.c_int),
        ("archive_read_data", [pointer, pointer, ctypes.c_size_t], ctypes.c_ssize_t),
        ("archive_read_free", [pointer], ctypes.c_int),
        ("archive_error_string", [pointer], ctypes.c_char_p),
        ("archive_entry_pathname_utf8", [pointer], ctypes.c_char_p),
        ("archive_entry_size", [pointer], ctypes.c_int64),
        ("archive_entry_mode", [pointer], ctypes.c_uint),
        ("archive_entry_mtime", [pointer], ctypes.c_int64),
        ("archive_entry_mtime_nsec", [pointer], ctypes.c_long),
        ("archive_entry_is_encrypted", [pointer], ctypes.c_int),
        ("archive_version_string", [], ctypes.c_char_p),
    ]
    for name, arguments, result in signatures:
        function = getattr(lib, name)
        function.argtypes, function.restype = arguments, result
    reader = lib.archive_read_new()
    try:
        assert lib.archive_read_support_format_rar5(reader) == 0
        assert lib.archive_read_open_filename(reader, bytes(path), CHUNK) == 0, lib.archive_error_string(reader)
        entry = pointer()
        buffer = ctypes.create_string_buffer(CHUNK)
        seen = set()
        receipt = []
        while True:
            status = lib.archive_read_next_header(reader, ctypes.byref(entry))
            if status == 1:
                break
            assert status == 0, lib.archive_error_string(reader)
            name = lib.archive_entry_pathname_utf8(entry).decode("utf-8").rstrip("/")
            assert name in expected and name not in seen, name
            seen.add(name)
            want = expected[name]
            mode = lib.archive_entry_mode(entry)
            assert stat.S_IFMT(mode) == (stat.S_IFDIR if want["directory"] else stat.S_IFREG), (name, mode)
            assert lib.archive_entry_size(entry) == want["size"], name
            assert lib.archive_entry_is_encrypted(entry) == 0, name
            if want.get("mode") is not None:
                assert mode & 0xfff == want["mode"] & 0xfff, (name, oct(mode), want["mode"])
            mtime = lib.archive_entry_mtime(entry) * 1_000_000 + lib.archive_entry_mtime_nsec(entry) // 1000
            if want.get("mtimeMicros") is not None:
                # libarchive 3.7.4's RAR5 reader exposes whole-second times.
                # The independent header parser above checks exact precision;
                # newer libarchive builds must also agree on any precision
                # they report instead of being silently rounded here.
                assert mtime // 1_000_000 == want["mtimeMicros"] // 1_000_000, (name, mtime, want["mtimeMicros"])
                if lib.archive_entry_mtime_nsec(entry):
                    assert mtime == want["mtimeMicros"], (name, mtime, want["mtimeMicros"])
            total = 0
            digest = hashlib.sha256()
            while not want["directory"]:
                count = lib.archive_read_data(reader, buffer, CHUNK)
                assert count >= 0, lib.archive_error_string(reader)
                if count == 0:
                    break
                chunk = buffer.raw[:count]
                if want.get("sentinelZeros"):
                    middle = chunk
                    if total == 0:
                        assert middle[0] == 0x43
                        middle = middle[1:]
                    if total + count == want["size"]:
                        assert middle[-1] == 0xa5
                        middle = middle[:-1]
                    assert middle.count(0) == len(middle), "Unexpected nonzero payload byte"
                total += count
                digest.update(chunk)
            assert total == want["size"], (name, total, want["size"])
            if not want["directory"]:
                assert digest.hexdigest() == want["sha256"], name
            receipt.append({"name": name, "bytes": total, "sha256": digest.hexdigest(), "mtimeMicros": mtime})
        assert seen == expected.keys(), (seen, expected.keys())
        metadata = path.stat()
        print(json.dumps({"oracle": lib.archive_version_string().decode(), "exactMetadata": "Python public-spec header parser", "archive": path.name, "archiveBytes": metadata.st_size, "allocatedBytes": metadata.st_blocks * 512, "result": "PASS", "members": receipt}, ensure_ascii=False))
    finally:
        lib.archive_read_free(reader)


if __name__ == "__main__":
    check(Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text()))
