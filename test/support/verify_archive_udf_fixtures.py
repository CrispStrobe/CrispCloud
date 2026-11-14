#!/usr/bin/env python3
"""Verify committed external UDF image hashes and descriptor CRCs in Python.

This is a fixed-fixture integrity control, not a second general UDF reader.
Sector inventories describe the known independently mastered reference media.
No Dart parser or Dart fixture assembler is used for CRC validation.
"""

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 CrispCloud contributors

import argparse
import binascii
import json
from pathlib import Path
import struct

from check_archive_udf import read_reference_images, sha

SECTOR = 2048


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    manifest, _, fixtures = read_reference_images(root)
    report = {"schema": 1, "oracle": "Python binascii.crc_hqx with initial remainder0; fixed external-master descriptor inventory", "cases": []}
    for name, image in fixtures.items():
        checked = []

        def descriptor(offset, identifier, location, length):
            tag, version, checksum, reserved, serial, crc, crc_length, actual_location = struct.unpack_from("<HHBBHHHI", image, offset)
            if (tag, version, reserved, actual_location, crc_length) != (identifier, 2, 0, location, length - 16):
                raise SystemExit("Unexpected descriptor layout in " + name + " at " + str(offset))
            if (sum(image[offset : offset + 4]) + sum(image[offset + 5 : offset + 16])) & 255 != checksum:
                raise SystemExit("Tag checksum failure in " + name)
            if binascii.crc_hqx(image[offset + 16 : offset + length], 0) != crc:
                raise SystemExit("Descriptor CRC failure in " + name)
            checked.append({"byte_offset": offset, "identifier": identifier, "location": location, "crc_bytes": crc_length, "crc16": crc})

        for base in (32, 48):
            for index, identifier in enumerate((1, 4, 5, 6, 7, 8)):
                offset = (base + index) * SECTOR
                length = 440 + struct.unpack_from("<I", image, offset + 264)[0] if identifier == 6 else 24 + struct.unpack_from("<I", image, offset + 20)[0] * 8 if identifier == 7 else 512
                descriptor(offset, identifier, base + index, length)
        integrity = 64 * SECTOR
        maps, implementation = struct.unpack_from("<II", image, integrity + 72)
        descriptor(integrity, 9, 64, 80 + maps * 8 + implementation)
        descriptor(65 * SECTOR, 8, 65, 512)
        descriptor(256 * SECTOR, 2, 256, 512)
        descriptor((len(image) // SECTOR - 1) * SECTOR, 2, len(image) // SECTOR - 1, 512)
        descriptor(257 * SECTOR, 256, 0, 512)
        descriptor(258 * SECTOR, 8, 1, 512)
        for sector in (259, 261, 263, 264, 265, 266):
            offset = sector * SECTOR
            extended_attributes, allocations = struct.unpack_from("<II", image, offset + 168)
            descriptor(offset, 261, sector - 257, 176 + extended_attributes + allocations)
        for file_entry_sector, directory_sector in ((259, 260), (261, 262)):
            length = struct.unpack_from("<Q", image, file_entry_sector * SECTOR + 56)[0]
            position = 0
            while position < length:
                offset = directory_sector * SECTOR + position
                filename_length = image[offset + 19]
                implementation_length = struct.unpack_from("<H", image, offset + 36)[0]
                descriptor_length = (38 + filename_length + implementation_length + 3) // 4 * 4
                descriptor(offset, 257, directory_sector - 257, descriptor_length)
                position += descriptor_length
            if position != length:
                raise SystemExit("Directory record boundaries differ in " + name)
        report["cases"].append({"name": name, "image_sha256": sha(image), "descriptor_checks": checked, "descriptor_count": len(checked)})
    report["passed"] = len(report["cases"])
    report["descriptor_crc_checks"] = sum(row["descriptor_count"] for row in report["cases"])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "descriptor_crc_checks": report["descriptor_crc_checks"]}))


if __name__ == "__main__":
    main()
