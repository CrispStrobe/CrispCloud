"""Check emitted writer outputs with native tools, independently of Dart.

Requires libarchive, GNU ar and dpkg-deb. See the companion Dart producer.
"""

import ctypes as c
import hashlib
import json
import locale
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Supply the directory emitted by the Dart producer.")
    directory = Path(sys.argv[1])
    locale.setlocale(locale.LC_ALL, "")
    lib = c.CDLL("libarchive.so.13")
    lib.archive_version_string.restype = c.c_char_p
    lib.archive_read_new.restype = c.c_void_p
    for name in (
        "archive_read_support_format_all",
        "archive_read_support_filter_all",
        "archive_read_free",
    ):
        getattr(lib, name).argtypes = [c.c_void_p]
    lib.archive_read_open_memory.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_read_next_header.argtypes = [c.c_void_p, c.POINTER(c.c_void_p)]
    lib.archive_read_data_block.argtypes = [
        c.c_void_p,
        c.POINTER(c.c_void_p),
        c.POINTER(c.c_size_t),
        c.POINTER(c.c_int64),
    ]
    lib.archive_error_string.argtypes = [c.c_void_p]
    lib.archive_error_string.restype = c.c_char_p
    lib.archive_entry_pathname.argtypes = [c.c_void_p]
    lib.archive_entry_pathname.restype = c.c_char_p
    for name in ("size", "uid", "gid", "mtime"):
        fn = getattr(lib, f"archive_entry_{name}")
        fn.argtypes = [c.c_void_p]
        fn.restype = c.c_int64
    lib.archive_entry_mode.argtypes = [c.c_void_p]
    lib.archive_entry_mode.restype = c.c_uint

    def read(path):
        raw = path.read_bytes()
        memory = c.create_string_buffer(raw)
        reader = lib.archive_read_new()
        entry = c.c_void_p()
        entries = []
        try:
            assert lib.archive_read_support_format_all(reader) == 0
            assert lib.archive_read_support_filter_all(reader) == 0
            assert lib.archive_read_open_memory(reader, memory, len(raw)) == 0, (
                path,
                lib.archive_error_string(reader),
            )
            while True:
                status = lib.archive_read_next_header(reader, c.byref(entry))
                if status == 1:
                    break
                assert status == 0, (path, status, lib.archive_error_string(reader))
                name = lib.archive_entry_pathname(entry).decode("utf-8")
                digest = hashlib.sha256()
                consumed = 0
                while True:
                    block = c.c_void_p()
                    length = c.c_size_t()
                    offset = c.c_int64()
                    status = lib.archive_read_data_block(
                        reader, c.byref(block), c.byref(length), c.byref(offset)
                    )
                    # Use the block API: libarchive 3.7.4's XAR reader returns
                    # an aggregate archive offset at EOF. archive_read_data
                    # interprets it as trailing sparse data in later members.
                    # Successful blocks have the correct per-member offsets.
                    # See xar_read_data's abort_read_data in the pinned source:
                    # github.com/libarchive/libarchive/blob/v3.7.4/libarchive/
                    # archive_read_support_format_xar.c
                    if status == 1:
                        break
                    assert status == 0, (path, name, lib.archive_error_string(reader))
                    assert offset.value == consumed, (path, name, offset.value, consumed)
                    digest.update(c.string_at(block, length.value))
                    consumed += length.value
                size = lib.archive_entry_size(entry)
                assert consumed == size, (path, name, consumed, size)
                # libarchive exposes GNU's name table as a zero-byte record;
                # GNU ar's member listing, like the app's model, excludes it.
                if name == "//":
                    continue
                entries.append(
                    {
                        "path": name.rstrip("/"),
                        "size": size,
                        "mode": lib.archive_entry_mode(entry),
                        "uid": lib.archive_entry_uid(entry),
                        "gid": lib.archive_entry_gid(entry),
                        "mtime": lib.archive_entry_mtime(entry),
                        "sha256": digest.hexdigest(),
                    }
                )
            return entries
        finally:
            lib.archive_read_free(reader)

    print(lib.archive_version_string().decode())
    for case in json.loads((directory / "manifest.json").read_text()):
        path = directory / case["file"]
        actual = read(path)
        expected = (
            read(directory / case["source"])
            if "source" in case
            else case["entries"]
        )
        assert actual == expected, (path.name, actual, expected)
        if case["kind"] == "ar":
            listed = subprocess.run(
                ["ar", "t", str(path)], check=True, capture_output=True, text=True
            ).stdout.splitlines()
            assert listed == [entry["path"] for entry in expected], (path, listed)
        if case["kind"] == "deb":
            with tempfile.TemporaryDirectory(dir=directory.resolve()) as temporary:
                environment = dict(os.environ, TMPDIR=temporary)
                subprocess.run(
                    ["dpkg-deb", "--info", str(path)],
                    check=True,
                    capture_output=True,
                    env=environment,
                )
                contents = subprocess.run(
                    ["dpkg-deb", "--contents", str(path)],
                    check=True,
                    capture_output=True,
                    text=True,
                    env=environment,
                ).stdout
            assert "usr/share/crisp/data.txt" in contents
        print(f"PASS {path.name}: {len(actual)} members, content and metadata")
    print("All native package writer checks passed.")


if __name__ == "__main__":
    main()
