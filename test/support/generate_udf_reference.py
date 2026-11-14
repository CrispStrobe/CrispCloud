#!/usr/bin/env python3
"""Master independent UDF reference media with an external genisoimage.

The executable is a test-only oracle and is never a runtime dependency. Its
source is not copied into this repository. Only original payloads and generated
filesystem data are retained. Timestamps and the generated volume-set identifier
are normalized after mastering, with descriptor CRCs recalculated using Python's
standard binascii.crc_hqx. The explicit UDF-only and fragmented variants are
derived from the independently mastered image, not separately mastered media.
"""

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 CrispCloud contributors

from __future__ import annotations

import argparse
import base64
import binascii
import gzip
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile

SECTOR = 2048
EPOCH = 946684800
PAYLOADS = {
    "hello.txt": b"CrispCloud independent UDF reference\n",
    "empty.bin": b"",
    "caf\u00e9-\u96ea.txt": "Caf\u00e9, \u96ea and UDF!\n".encode(),
    "nested/payload.bin": bytes((i * 37 + 11) % 251 for i in range(8193)),
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def retag(image: bytearray, offset: int, crc_length: int | None = None) -> None:
    if crc_length is None:
        crc_length = u16(image, offset + 10)
    struct.pack_into("<H", image, offset + 10, crc_length)
    crc = binascii.crc_hqx(image[offset + 16 : offset + 16 + crc_length], 0)
    struct.pack_into("<H", image, offset + 8, crc)
    image[offset + 4] = 0
    image[offset + 4] = sum(image[offset : offset + 16]) & 255


def timestamp() -> bytes:
    # UDF local-time type 1, UTC offset 0, 2000-01-01 00:00:00.
    return struct.pack("<HHBBBBBBBB", 0x1000, 2000, 1, 1, 0, 0, 0, 0, 0, 0)


def normalize(image: bytes) -> bytes:
    data = bytearray(image)
    for sector in range(32, len(data) // SECTOR):
        at = sector * SECTOR
        tag = u16(data, at)
        if tag not in (1, 9, 256, 261):
            continue
        # Ignore incidental matching payload bytes: require a valid descriptor.
        checksum = sum(data[at : at + 4]) + sum(data[at + 5 : at + 16])
        crc_len = u16(data, at + 10)
        if (checksum & 255) != data[at + 4] or crc_len > SECTOR - 16:
            continue
        if binascii.crc_hqx(data[at + 16 : at + 16 + crc_len], 0) != u16(data, at + 8):
            continue
        if tag == 1:
            volume_set = b"\x08CRISPCLOUD-REFERENCE"
            data[at + 72 : at + 200] = bytes(128)
            data[at + 72 : at + 72 + len(volume_set)] = volume_set
            data[at + 199] = len(volume_set)
            data[at + 376 : at + 388] = timestamp()
        elif tag in (9, 256):
            data[at + 16 : at + 28] = timestamp()
        else:
            for pos in (72, 84, 96):
                data[at + pos : at + pos + 12] = timestamp()
        retag(data, at)
    return bytes(data)


def udf_only(image: bytes) -> bytes:
    data = bytearray(image)
    records = []
    for sector in range(16, 32):
        block = image[sector * SECTOR : (sector + 1) * SECTOR]
        if block[1:6] in (b"BEA01", b"NSR02", b"TEA01"):
            records.append(block)
    if [r[1:6] for r in records] != [b"BEA01", b"NSR02", b"TEA01"]:
        raise ValueError("Unexpected external generator VRS")
    data[16 * SECTOR : 32 * SECTOR] = bytes(16 * SECTOR)
    data[16 * SECTOR : 19 * SECTOR] = b"".join(records)
    return bytes(data)


def fragment(image: bytes) -> tuple[bytes, dict]:
    data = bytearray(image)
    partitions = []
    entries = []
    for sector in range(32, len(image) // SECTOR):
        at = sector * SECTOR
        tag = u16(image, at)
        if tag == 5:
            partitions.append(u32(image, at + 188))
        if tag == 261 and struct.unpack_from("<Q", image, at + 56)[0] == 8193:
            entries.append(at)
    if len(entries) != 1 or len(set(partitions)) != 1:
        raise ValueError("Unexpected external generator partition/file layout")
    at = entries[0]
    if u16(image, at + 34) & 7 or u32(image, at + 168) != 0 or u32(image, at + 172) != 8:
        raise ValueError("Expected one short allocation descriptor without EAs")
    block = u32(image, at + 180)
    physical = (partitions[0] + block) * SECTOR
    expected = PAYLOADS["nested/payload.bin"]
    if image[physical : physical + len(expected)] != expected:
        raise ValueError("Mastered payload differs before fragmentation")
    sections = [(2048, block + 4), (4096, block), (2049, block + 2)]
    data[physical : physical + 5 * SECTOR] = bytes(5 * SECTOR)
    logical = 0
    for length, location in sections:
        dest = (partitions[0] + location) * SECTOR
        data[dest : dest + length] = expected[logical : logical + length]
        logical += length
    descriptors = b"".join(struct.pack("<II", length, location) for length, location in sections)
    struct.pack_into("<I", data, at + 172, len(descriptors))
    data[at + 176 : at + 176 + len(descriptors)] = descriptors
    retag(data, at, 160 + len(descriptors))
    return bytes(data), {
        "file_entry_byte_offset": at,
        "partition_start_sector": partitions[0],
        "sections": [{"length": length, "relative_lba": location} for length, location in sections],
    }


def master(executable: Path, directory: Path) -> tuple[bytes, list[str]]:
    source = directory / "input"
    source.mkdir(parents=True)
    for name, payload in PAYLOADS.items():
        target = source / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
    for path in [*source.rglob("*"), source]:
        os.utime(path, (EPOCH, EPOCH))
    output = directory / "mastered.iso"
    command = [str(executable), "-quiet", "-udf", "-J", "-iso-level", "3", "-V", "CRISP_UDF_REF", "-input-charset", "utf-8", "-creation-date", str(EPOCH), "-o", str(output), str(source)]
    subprocess.run(command, check=True, env={**os.environ, "TZ": "UTC", "LC_ALL": "C.UTF-8"})
    return normalize(output.read_bytes()), command[1:-3] + ["-o", "<output.iso>", "<input-directory>"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--genisoimage", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    executable = args.genisoimage.resolve()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="crisp-udf-") as temporary:
        bridge, command = master(executable, Path(temporary))
    fragmented, layout = fragment(udf_only(bridge))
    variants = {"mastered-bridge": bridge, "derived-udf-only": udf_only(bridge), "derived-fragmented": fragmented}
    manifest = {
        "schema": 1,
        "generator": {"version": subprocess.check_output([str(executable), "--version"], text=True).strip(), "sha256": sha(executable.read_bytes()), "arguments": command},
        "normalization": "Only UDF descriptor timestamps and volume-set identifier; CRC/tag checks recomputed with Python stdlib. ISO timestamps set by generator option and source metadata.",
        "variant_origin": {"mastered-bridge": "External genisoimage UDF1.02/ISO/Joliet master with deterministic metadata normalization.", "derived-udf-only": "Same UDF filesystem; ISO VRS removed and BEA01/NSR02/TEA01 moved to sectors16-18.", "derived-fragmented": "Derived UDF-only; one real file entry changed to three nonascending short extents; original payload redistributed within its original five sectors."},
        "payloads": {name: {"bytes": len(payload), "sha256": sha(payload)} for name, payload in sorted(PAYLOADS.items())},
        "fragmented_layout": layout,
        "fixtures": {name: {"bytes": len(data), "sha256": sha(data)} for name, data in variants.items()},
    }
    outputs = {name + ".iso": data for name, data in variants.items()}
    outputs["udf-reference-manifest.json"] = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode()
    dart = ["// Generated by generate_udf_reference.py; see udf-reference-manifest.json.", "// Original payloads and fixture normalization: SPDX-License-Identifier: MIT.", "import 'dart:convert';", "import 'dart:typed_data';", "", "import 'package:archive/archive.dart' as archive;", "", "const udfReferenceImages = <String, String>{"]
    for name, data in variants.items():
        encoded = base64.b64encode(gzip.compress(data, mtime=0)).decode()
        dart.append("  '" + name + "':")
        for pos in range(0, len(encoded), 100):
            dart.append("      '" + encoded[pos : pos + 100] + "'")
        dart[-1] += ","
    dart += ["};", "", "Uint8List udfReferenceBytes(String name) => Uint8List.fromList(", "  const archive.GZipDecoder().decodeBytes(base64Decode(udfReferenceImages[name]!)),", ");", "", "const udfReferencePayloads = <String, String>{"]
    for name, payload in PAYLOADS.items():
        # Expected content patterns are generated independently in the driver;
        # only hashes are included here, keeping this fixture small.
        dart.append("  " + json.dumps(name, ensure_ascii=False) + ": '" + sha(payload) + "',")
    dart += ["};", ""]
    outputs["archive_udf_reference_data.dart"] = "\n".join(dart).encode()
    for name, data in outputs.items():
        target = args.output_dir / name
        if args.check:
            if not target.is_file() or target.read_bytes() != data:
                raise SystemExit("Reference reproduction differs: " + name)
        else:
            target.write_bytes(data)
    print(json.dumps({"fixtures": manifest["fixtures"], "payloads": len(PAYLOADS), "reproduction_check": args.check}))


if __name__ == "__main__":
    main()
