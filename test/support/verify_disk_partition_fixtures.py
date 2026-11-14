#!/usr/bin/env python3
"""Independently verify synthetic GPT fixtures with Python struct and zlib.

No disk-writing tool is invoked. This reads the SDK driver's sparse metadata
export and checks both header and array CRCs plus fixed format relationships.
"""

# Copyright 2026 CrispCloud contributors
# SPDX-License-Identifier: MIT

import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zlib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default="dart", help="Dart SDK executable")
    args = parser.parse_args()
    driver = Path(__file__).with_name("disk_partition_web_acceptance.dart")
    result = subprocess.run(
        [args.dart, str(driver), "--fixtures-json"],
        check=True, capture_output=True, text=True,
    )
    fixtures = json.loads(result.stdout)
    receipts = []
    checks = 0
    for fixture in fixtures:
        sector = fixture["sector_bytes"]
        total = fixture["total_bytes"]
        sectors = total // sector
        mbr = base64.b64decode(fixture["mbr"], validate=True)
        assert mbr[510:512] == b"\x55\xaa"
        assert mbr[450] == 0xEE
        assert struct.unpack_from("<II", mbr, 454) == (1, min(sectors - 1, 0xFFFFFFFF))
        receipt = {"sector_bytes": sector, "total_bytes": total, "mirrors": []}
        tables = []
        for role, self_lba, alternate in [("primary", 1, sectors - 1), ("backup", sectors - 1, 1)]:
            header = base64.b64decode(fixture[f"{role}_header"], validate=True)
            table = base64.b64decode(fixture[f"{role}_table"], validate=True)
            assert len(header) == sector and header[:8] == b"EFI PART"
            revision, size, declared_crc, reserved = struct.unpack_from("<IIII", header, 8)
            assert revision == 0x10000 and 92 <= size <= sector and reserved == 0
            copy = bytearray(header[:size])
            copy[16:20] = bytes(4)
            actual_crc = zlib.crc32(copy)
            assert actual_crc == declared_crc
            checks += 1
            mine, other, first, last = struct.unpack_from("<QQQQ", header, 24)
            assert (mine, other) == (self_lba, alternate)
            assert 1 < first <= last < sectors - 1
            table_lba, count, entry_size, declared_table_crc = struct.unpack_from("<QIII", header, 72)
            assert entry_size >= 128 and entry_size & (entry_size - 1) == 0
            assert len(table) == count * entry_size
            actual_table_crc = zlib.crc32(table)
            assert actual_table_crc == declared_table_crc
            checks += 1
            assert 0 <= table_lba * sector <= total - len(table)
            part_start, part_end = struct.unpack_from("<QQ", table, 32)
            assert first <= part_start <= part_end <= last
            assert table[56:128].decode("utf-16-le").split("\0", 1)[0] == "CrispCloud test"
            receipt["mirrors"].append({
                "role": role,
                "header_crc32": f"{actual_crc:08x}",
                "table_crc32": f"{actual_table_crc:08x}",
                "header_sha256": hashlib.sha256(header).hexdigest(),
                "table_sha256": hashlib.sha256(table).hexdigest(),
            })
            tables.append(table)
        assert tables[0] == tables[1]
        receipts.append(receipt)
    print(json.dumps({"fixtures_verified": len(receipts), "crc_checks": checks,
                      "oracle": "Python standard-library zlib.crc32", "fixtures": receipts}, indent=2))


if __name__ == "__main__":
    main()
