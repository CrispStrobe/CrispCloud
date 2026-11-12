#!/usr/bin/env python3
"""Generate original LZMA-alone fixtures or independently verify Dart output."""

import hashlib
import lzma
from pathlib import Path
import sys


def random_data(size):
    value = 0x13579BDF
    result = bytearray()
    for _ in range(size):
        value = (value * 1664525 + 1013904223) & 0xFFFFFFFF
        result.append(value >> 24)
    return bytes(result)


def checked_decode(packed):
    decoder = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE, memlimit=96 << 20)
    actual = decoder.decompress(packed, max_length=(64 << 20) + 1)
    if len(actual) > 64 << 20 or not decoder.eof or decoder.unused_data:
        raise RuntimeError("Incomplete, oversized, or trailing LZMA stream")
    return actual


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "verify":
        packed, expected = (Path(name).read_bytes() for name in sys.argv[2:])
        actual = checked_decode(packed)
        if actual != expected:
            raise RuntimeError("Independent LZMA output differs from its source")
        print(f"liblzma: verified {len(packed)} compressed / {len(actual)} decoded bytes")
        return
    if len(sys.argv) != 2 or sys.argv[1] != "generate":
        raise SystemExit("Usage: check_archive_lzma.py generate | verify frame source")
    destination = Path(__file__).resolve().parents[1] / "fixtures/archives"
    destination.mkdir(parents=True, exist_ok=True)
    cases = [
        ("default", b"Independent LZMA-alone fixture\n" * 10000,
         dict(id=lzma.FILTER_LZMA1, dict_size=8 << 20)),
        ("properties", b"Non-default literal positions\x00\xff" * 500,
         dict(id=lzma.FILTER_LZMA1, dict_size=65536, lc=1, lp=2, pb=4)),
        ("distance", random_data(8192) * 4,
         dict(id=lzma.FILTER_LZMA1, dict_size=65536)),
        ("empty", b"", dict(id=lzma.FILTER_LZMA1, dict_size=4096)),
    ]
    for name, payload, settings in cases:
        packed = lzma.compress(payload, format=lzma.FORMAT_ALONE, filters=[settings])
        assert checked_decode(packed) == payload
        path = destination / f"lzma-reference-{name}.lzma"
        path.write_bytes(packed)
        print(f"{path.name}: {len(packed)} bytes; "
              f"SHA-256 {hashlib.sha256(packed).hexdigest()}")


if __name__ == "__main__":
    main()
