"""Generate original UNIX compress fixtures with libarchive, verify with gzip.

No third-party source or payload is copied. Requires system libarchive and gzip;
neither is an application dependency. Run from any directory with Python 3.
"""

from pathlib import Path
import argparse
import ctypes as c
import ctypes.util
import hashlib
import json
import shutil
import subprocess


ROOT = Path(__file__).resolve().parent
LIB = c.CDLL(ctypes.util.find_library('archive'))


def function(name, result, *arguments):
    value = getattr(LIB, name)
    value.restype = result
    value.argtypes = arguments
    return value


version = function('archive_version_string', c.c_char_p)
new = function('archive_write_new', c.c_void_p)
raw = function('archive_write_set_format_raw', c.c_int, c.c_void_p)
compress = function('archive_write_add_filter_compress', c.c_int, c.c_void_p)
block_size = function('archive_write_set_bytes_per_block', c.c_int, c.c_void_p, c.c_int)
last_block = function('archive_write_set_bytes_in_last_block', c.c_int, c.c_void_p, c.c_int)
open_memory = function('archive_write_open_memory', c.c_int, c.c_void_p, c.c_void_p, c.c_size_t, c.POINTER(c.c_size_t))
entry_new = function('archive_entry_new', c.c_void_p)
entry_path = function('archive_entry_set_pathname', None, c.c_void_p, c.c_char_p)
entry_type = function('archive_entry_set_filetype', None, c.c_void_p, c.c_uint)
entry_mode = function('archive_entry_set_perm', None, c.c_void_p, c.c_int)
entry_size = function('archive_entry_set_size', None, c.c_void_p, c.c_int64)
write_header = function('archive_write_header', c.c_int, c.c_void_p, c.c_void_p)
write_data = function('archive_write_data', c.c_ssize_t, c.c_void_p, c.c_void_p, c.c_size_t)
close = function('archive_write_close', c.c_int, c.c_void_p)
free = function('archive_write_free', c.c_int, c.c_void_p)
entry_free = function('archive_entry_free', None, c.c_void_p)
error = function('archive_error_string', c.c_char_p, c.c_void_p)


def encode(payload):
    archive, entry = new(), entry_new()
    output = c.create_string_buffer(max(4096, len(payload) * 2 + 1024))
    used = c.c_size_t()

    def checked(status):
        if status < 0:
            raise RuntimeError(error(archive))

    try:
        checked(raw(archive))
        checked(compress(archive))
        checked(block_size(archive, 0))
        checked(last_block(archive, 1))
        checked(open_memory(archive, output, len(output), c.byref(used)))
        entry_path(entry, b'payload')
        entry_type(entry, 0o100000)
        entry_mode(entry, 0o644)
        entry_size(entry, len(payload))
        checked(write_header(archive, entry))
        if payload:
            source = c.create_string_buffer(payload)
            assert write_data(archive, source, len(payload)) == len(payload)
        checked(close(archive))
        return output.raw[:used.value]
    finally:
        entry_free(entry)
        free(archive)


def literal_codes(payload, bits=16, block=True, reset_at=None):
    """Original wire-format builder for externally checked corner fixtures."""
    output = bytearray([0x1f, 0x9d, bits | (0x80 if block else 0)])
    cursor = section = 24
    width, next_code, previous = 9, (257 if block else 256), False

    def put(code):
        nonlocal cursor
        for offset in range(width):
            byte = cursor // 8
            if byte == len(output):
                output.append(0)
            if code & (1 << offset):
                output[byte] |= 1 << (cursor % 8)
            cursor += 1

    def align():
        nonlocal cursor, section
        group = width * 8
        cursor = section + ((cursor - section + group - 1) // group) * group
        output.extend(b'\0' * (cursor // 8 - len(output)))
        section = cursor

    for index, value in enumerate(payload):
        if reset_at is not None and index == reset_at:
            assert block
            put(256)
            align()
            width, next_code, previous = 9, 257, False
        put(value)
        if previous and next_code < (1 << bits):
            next_code += 1
        previous = True
        if width < bits and next_code == (1 << width):
            align()
            width += 1
    return bytes(output)


def random_bytes(length):
    state = 0x12345678
    output = bytearray()
    for _ in range(length):
        state = (1664525 * state + 1013904223) & 0xffffffff
        output.append(state >> 24)
    return bytes(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ncompress', default=shutil.which('compress'), help='path to public-domain ncompress 5.1 or later')
    options = parser.parse_args()
    if not options.ncompress:
        parser.error('--ncompress is required for independently checked 9-bit streams')

    def nine_bits(data):
        return subprocess.run([options.ncompress, '-cf', '-b', '9'], input=data, capture_output=True, check=True).stdout

    cases = {
        'compress-reference-empty.Z': (b'', literal_codes),
        'compress-reference-text.Z': (b'CrispCloud UNIX compress reference.\n' * 1200, encode),
        'compress-reference-width-clear.Z': (
            b'CrispCloud compressed dictionary growth.\n' * 6000 + random_bytes(180000), encode),
        'compress-reference-nine-bit.Z': (
            bytes(range(256)) * 5, nine_bits),
        'compress-reference-nonblock.Z': (
            bytes(range(256)) * 18, lambda data: literal_codes(data, bits=13, block=False)),
        'compress-reference-clear.Z': (
            bytes(range(256)) * 18, lambda data: literal_codes(data, bits=13, reset_at=1301)),
    }
    records = {'encoder': version().decode(), 'nine_bit_encoder': 'public-domain ncompress 5.1', 'files': []}
    for name, (payload, encoder) in cases.items():
        packed = encoder(payload)
        result = subprocess.run([options.ncompress, '-dc'], input=packed, capture_output=True, check=True)
        assert result.stdout == payload, name
        if encoder is not nine_bits:
            result = subprocess.run(['gzip', '-dc'], input=packed, capture_output=True, check=True)
            assert result.stdout == payload, name
        (ROOT / name).write_bytes(packed)
        records['files'].append({
            'name': name,
            'encoder': 'libarchive raw/compress' if encoder is encode else 'ncompress 5.1 -b9' if encoder is nine_bits else 'original literal-code builder',
            'reference_decoders': ['ncompress 5.1'] if encoder is nine_bits else ['ncompress 5.1', 'GNU gzip'],
            'packed_bytes': len(packed),
            'packed_sha256': hashlib.sha256(packed).hexdigest(),
            'decoded_bytes': len(payload),
            'decoded_sha256': hashlib.sha256(payload).hexdigest(),
        })
    (ROOT / 'compress-reference-manifest.json').write_text(json.dumps(records, indent=2) + '\n')
    print(json.dumps(records, indent=2))


if __name__ == '__main__':
    main()
