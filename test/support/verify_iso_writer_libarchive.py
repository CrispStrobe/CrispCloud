"""Independent ISO writer check. Requires a system libarchive, never app runtime.

python3 test/support/verify_iso_writer_libarchive.py OUTPUT_DIRECTORY
The companion Dart generator writes writer.iso and expected.json there.
"""
import ctypes as c
import ctypes.util
import hashlib
import json
import sys
from pathlib import Path


def verify(directory: Path) -> None:
    library = ctypes.util.find_library("archive")
    if library is None:
        raise RuntimeError("Independent verification needs system libarchive")
    lib = c.CDLL(library)
    lib.archive_version_string.restype = c.c_char_p
    lib.archive_read_new.restype = c.c_void_p
    for name in ("archive_read_support_format_iso9660", "archive_read_free"):
        getattr(lib, name).argtypes = [c.c_void_p]
    lib.archive_read_open_filename.argtypes = [c.c_void_p, c.c_char_p, c.c_size_t]
    lib.archive_read_next_header.argtypes = [c.c_void_p, c.POINTER(c.c_void_p)]
    lib.archive_read_data.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_read_data.restype = c.c_ssize_t
    for name in ("archive_entry_pathname", "archive_error_string"):
        getattr(lib, name).argtypes = [c.c_void_p]
        getattr(lib, name).restype = c.c_char_p
    for name in ("archive_entry_mode", "archive_entry_filetype"):
        getattr(lib, name).argtypes = [c.c_void_p]
        getattr(lib, name).restype = c.c_uint
    for name in ("archive_entry_size", "archive_entry_mtime"):
        getattr(lib, name).argtypes = [c.c_void_p]
        getattr(lib, name).restype = c.c_int64

    expected = json.loads((directory / "expected.json").read_text())
    actual = {}
    archive = lib.archive_read_new()
    entry = c.c_void_p()
    lib.archive_read_support_format_iso9660(archive)
    try:
        assert lib.archive_read_open_filename(
            archive, str(directory / "writer.iso").encode(), 65536
        ) == 0, lib.archive_error_string(archive)
        while True:
            result = lib.archive_read_next_header(archive, c.byref(entry))
            if result == 1:
                break
            assert result == 0, lib.archive_error_string(archive)
            name = lib.archive_entry_pathname(entry).decode("utf-8")
            if name == ".":
                continue
            folder = lib.archive_entry_filetype(entry) == 0x4000
            item = {
                "directory": folder,
                "size": 0 if folder else lib.archive_entry_size(entry),
                "mode": lib.archive_entry_mode(entry),
                "mtime": lib.archive_entry_mtime(entry),
            }
            if not folder:
                checksum = hashlib.sha256()
                buffer = c.create_string_buffer(65536)
                received = 0
                while True:
                    count = lib.archive_read_data(archive, buffer, len(buffer))
                    assert count >= 0, lib.archive_error_string(archive)
                    if count == 0:
                        break
                    received += count
                    checksum.update(buffer.raw[:count])
                assert received == item["size"], (name, received, item["size"])
                item["sha256"] = checksum.hexdigest()
            assert name not in actual, name
            actual[name] = item
    finally:
        lib.archive_read_free(archive)
    assert actual.keys() == expected.keys(), (
        "names differ", sorted(actual.keys() - expected.keys()),
        sorted(expected.keys() - actual.keys()),
    )
    for name, item in actual.items():
        assert item == expected[name], (name, item, expected[name])
    print(f"{lib.archive_version_string().decode()}: "
          f"{len(actual)} exact names, types, modes, times and payloads verified")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
