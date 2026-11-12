"""Read original Dart UNIX compress output using GNU gzip and native libarchive.

These external tools are validation-only and are never runtime dependencies.
The wire inspection counts code widths and dictionary resets independently of
the Dart decoder, while both native decoders must reproduce the original data.
"""
import ctypes as c
import ctypes.util
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile


def native_reader():
    lib = c.CDLL(ctypes.util.find_library('archive'))
    lib.archive_version_string.restype = c.c_char_p
    lib.archive_read_new.restype = c.c_void_p
    for name in ('archive_read_support_format_raw', 'archive_read_support_format_empty',
                 'archive_read_support_filter_compress', 'archive_read_free'):
        getattr(lib, name).argtypes = [c.c_void_p]
    lib.archive_read_open_memory.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_read_next_header.argtypes = [c.c_void_p, c.POINTER(c.c_void_p)]
    lib.archive_read_data.argtypes = [c.c_void_p, c.c_void_p, c.c_size_t]
    lib.archive_read_data.restype = c.c_ssize_t
    lib.archive_error_string.argtypes = [c.c_void_p]
    lib.archive_error_string.restype = c.c_char_p

    def read(packed):
        memory = c.create_string_buffer(packed)
        reader = lib.archive_read_new()
        entry = c.c_void_p()
        try:
            assert lib.archive_read_support_format_raw(reader) == 0
            assert lib.archive_read_support_format_empty(reader) == 0
            assert lib.archive_read_support_filter_compress(reader) == 0
            assert lib.archive_read_open_memory(reader, memory, len(packed)) == 0, lib.archive_error_string(reader)
            status = lib.archive_read_next_header(reader, c.byref(entry))
            if status == 1:
                return b''
            assert status == 0, lib.archive_error_string(reader)
            data = bytearray()
            buffer = c.create_string_buffer(32768)
            while True:
                count = lib.archive_read_data(reader, buffer, len(buffer))
                assert count >= 0, lib.archive_error_string(reader)
                if count == 0:
                    break
                data.extend(buffer.raw[:count])
            assert lib.archive_read_next_header(reader, c.byref(entry)) == 1
            return bytes(data)
        finally:
            lib.archive_read_free(reader)

    return lib.archive_version_string().decode(), read


def wire_profile(packed):
    assert packed[:2] == b'\x1f\x9d'
    maximum = packed[2] & 31
    assert packed[2] == 0x80 | maximum and maximum in (12, 14, 16)
    at = section = 24
    width, next_code, previous, resets = 9, 257, False, 0
    widths = set()

    def finish_group():
        nonlocal at, section
        end = section + ((at - section + width * 8 - 1) // (width * 8)) * width * 8
        assert end <= len(packed) * 8
        for bit in range(at, end):
            assert packed[bit // 8] & (1 << (bit % 8)) == 0
        at = section = end

    while len(packed) * 8 - at >= width:
        widths.add(width)
        code = sum(((packed[(at + bit) // 8] >> ((at + bit) % 8)) & 1) << bit
                   for bit in range(width))
        at += width
        if code == 256:
            finish_group()
            width, next_code, previous = 9, 257, False
            resets += 1
            continue
        assert code <= next_code and (previous or code < 256)
        if previous and next_code < 1 << maximum:
            next_code += 1
        previous = True
        if width < maximum and next_code == 1 << width:
            finish_group()
            width += 1
    assert len(packed) * 8 - at <= 7
    for bit in range(at, len(packed) * 8):
        assert packed[bit // 8] & (1 << (bit % 8)) == 0
    return widths, resets


def tar_entries(raw):
    result = []
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as archive:
        for member in archive:
            assert member.isdir() or member.isfile(), member.name
            data = b'' if member.isdir() else archive.extractfile(member).read()
            result.append({
                'path': member.name.rstrip('/'), 'directory': member.isdir(),
                'size': member.size, 'mode': member.mode, 'uid': member.uid,
                'gid': member.gid, 'uname': member.uname, 'gname': member.gname,
                'mtime': member.mtime, 'sha256': hashlib.sha256(data).hexdigest(),
            })
    return result


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Supply the directory emitted by emit_archive_unix_compress_profiles.dart.')
    directory = Path(sys.argv[1])
    version, read = native_reader()
    print(subprocess.run(['gzip', '--version'], capture_output=True, check=True, text=True).stdout.splitlines()[0])
    print(version)
    cases = json.loads((directory / 'manifest.json').read_text())
    for case in cases:
        packed = (directory / case['file']).read_bytes()
        source = (directory / case['source']).read_bytes()
        assert len(packed) == case['packedBytes']
        assert hashlib.sha256(packed).hexdigest() == case['packedSha256']
        assert len(source) == case['decodedBytes']
        assert hashlib.sha256(source).hexdigest() == case['decodedSha256']
        assert subprocess.run(['gzip', '-cd'], input=packed, capture_output=True, check=True).stdout == source
        assert read(packed) == source
        widths, resets = wire_profile(packed)
        assert packed[2] == 0x80 | case['maxBits']
        if case['file'].startswith('noise-reset-'):
            assert widths == set(range(9, case['maxBits'] + 1)), widths
            assert resets > 0, resets
        if 'tarEntries' in case:
            assert tar_entries(source) == case['tarEntries']
        if 'tarSource' in case:
            reference = (directory / case['tarSource']).read_bytes()
            expected = tar_entries(read(reference))
            if case['edited']:
                for entry in expected:
                    if not entry['directory']:
                        entry['size'] = len(b'changed')
                        entry['sha256'] = hashlib.sha256(b'changed').hexdigest()
            assert tar_entries(source) == expected
        print(f"PASS {case['file']}: {len(source)} bytes, widths {sorted(widths)}, {resets} resets")
    print(f'All {len(cases)} independent UNIX compress profile checks passed.')


if __name__ == '__main__':
    main()
