#!/usr/bin/env python3
"""Verify independent LZFSE streams inside UDIF using an external 7-Zip tool.

No 7-Zip code or binary is shipped with CrispCloud. This optional oracle uses
the existing independent UDIF fixture writer and original Apple encoder.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import zlib

from check_dmg_codecs import udif
from generate_lzfse_fixtures import PIN, Reference, vectors


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path,
                        help="Pinned Apple lzfse checkout")
    parser.add_argument("--sevenzip", required=True, type=Path,
                        help="External 7zz executable")
    parser.add_argument("--sevenzip-archive", type=Path,
                        help="Optional downloaded archive, for its provenance hash")
    parser.add_argument("--work-dir", type=Path,
                        help="Retain generated .dmg and expected .bin files")
    parser.add_argument("--allow-oracle-limitations", action="store_true",
                        help="Report known v1/stored/omitted-table 7-Zip limitations")
    args = parser.parse_args()
    sevenzip = args.sevenzip.resolve()
    info = subprocess.run([str(sevenzip), "i"], check=True,
                          capture_output=True, text=True, timeout=30)
    version = next(line.strip() for line in info.stdout.splitlines()
                   if line.strip().startswith("7-Zip"))
    results = []
    with tempfile.TemporaryDirectory(prefix="crisp-lzfse-dmg-") as temp:
        work = args.work_dir.resolve() if args.work_dir else Path(temp)
        work.mkdir(parents=True, exist_ok=True)
        reference = Reference(args.source.resolve(), work)
        fixtures = vectors(reference)
        selected = {name: fixtures[name] for name in (
            "lzvn", "v1", "v2", "v2_zero", "mixed", "multiblock",
            "v2_reused_tables", "v1_lzvn_reused_tables")}
        # Controls avoid a final stored padding block, isolating its failure in
        # the external tool from the original compressed block's correctness.
        for name in ("distance", "multiblock"):
            raw = fixtures[name][0]
            raw += bytes((-len(raw)) % 512)
            selected[name + "_sector_aligned"] = (raw, reference.encode(raw))
        parts = [fixtures[name] for name in ("v2", "lzvn", "v2")]
        selected["mixed_compressed"] = (
            b"".join(p[0] for p in parts),
            b"".join(p[1][:-4] for p in parts) + b"bvx$")
        raw = bytes(range(256)) * 2
        selected["stored_only"] = (raw, b"bvx-" + struct.pack("<I", len(raw))
                                   + raw + b"bvx$")
        for name, (raw, packed) in selected.items():
            pad = (-len(raw)) % 512
            if pad:
                # Sector alignment is a separate final stored block, preserving
                # every byte and boundary of the original compressed fixture.
                packed = (packed[:-4] + b"bvx-" + struct.pack("<I", pad)
                          + bytes(pad) + b"bvx$")
                raw += bytes(pad)
            assert reference.decode(packed, raw), name
            image_bytes = udif(raw, packed, 0x80000007)
            # Re-read the independently built UDIF map. Its CRC covers the
            # complete sector-aligned partition, including any zero padding.
            trailer = image_bytes[-512:]
            xml_offset, xml_length = struct.unpack_from(">QQ", trailer, 216)
            plist = plistlib.loads(image_bytes[xml_offset:xml_offset + xml_length])
            table = plist["resource-fork"]["blkx"][0]["Data"]
            checksum_type, checksum_bits, checksum = struct.unpack_from(">III", table, 64)
            assert (checksum_type, checksum_bits, checksum) == (2, 32, zlib.crc32(raw))
            assert struct.unpack_from(">Q", table, 16)[0] * 512 == len(raw)
            image = work / (name + ".dmg")
            image.write_bytes(image_bytes)
            (work / (name + ".bin")).write_bytes(raw)
            checked = subprocess.run(
                [str(sevenzip), "x", "-so", "-tdmg", str(image)],
                capture_output=True, timeout=30)
            record = {
                "fixture": name,
                "method": "0x80000007",
                "output_bytes": len(raw),
                "sector_padding_bytes": pad,
                "expected_output_sha256": sha256(raw),
                "packed_sha256": sha256(packed),
                "dmg_sha256": sha256(image_bytes),
                "udif_crc32": f"{checksum:08x}",
                "apple_strict_decoder": "passed",
            }
            if checked.returncode:
                # Keep every nonzero result as a failure in the report, even
                # when its stdout happens to contain all the expected bytes.
                error = checked.stderr.decode("utf-8", errors="replace").strip()
                record["sevenzip_extraction"] = "failed"
                record["sevenzip_exit_code"] = checked.returncode
                record["sevenzip_error"] = error
                record["output_matches_despite_error"] = checked.stdout == raw
            else:
                if checked.stdout != raw:
                    raise ValueError(f"{name}: independently extracted bytes differ")
                record["sevenzip_extraction"] = "passed"
                record["extracted_output_sha256"] = sha256(checked.stdout)
            results.append(record)
    report = {
        "reference_revision": PIN,
        "sevenzip_version": version,
        "sevenzip_binary_sha256": sha256(sevenzip.read_bytes()),
        "independent_dmg_extraction": results,
        "sevenzip_passes": sum(r["sevenzip_extraction"] == "passed" for r in results),
        "sevenzip_reported_errors": sum(r["sevenzip_extraction"] != "passed" for r in results),
    }
    if args.sevenzip_archive:
        report["sevenzip_archive_sha256"] = sha256(args.sevenzip_archive.read_bytes())
    print(json.dumps(report, indent=2))
    known_limitations = {
        "v1": "Unsupported Method", "mixed": "Data Error",
        "multiblock": "Data Error", "v2_reused_tables": "Data Error",
        "v1_lzvn_reused_tables": "Unsupported Method", "stored_only": "Data Error",
    }
    for result in results:
        if result["sevenzip_extraction"] == "passed":
            continue
        expected_error = known_limitations.get(result["fixture"])
        if (not args.allow_oracle_limitations or expected_error is None
                or result["sevenzip_exit_code"] != 2
                or expected_error not in result["sevenzip_error"]):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
