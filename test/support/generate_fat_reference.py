#!/usr/bin/env python3
"""Reproduce external FatFs reference volumes without bundling its source.

Copyright (c) 2026 CrispCloud contributors. SPDX-License-Identifier: MIT.
The separately supplied FatFs archive has its own BSD-style license.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM_URL = "https://elm-chan.org/fsw/ff/arc/ff16.zip"
UPSTREAM_SHA256 = "99f7dc1f7e095356e4a9e3dbe29959090d8b948afe2bbc5441e52fdf4b85449e"
UPSTREAM_FILES = {
    "ff.c": "dbeae3d7d22dbc070983e31af897fa5e43d29c726a0a240fe9589ffe2ec0ef1e",
    "ff.h": "42920ae4d6080bfc2a72d92a9969b5e94eeaff070e5e71d90da9ab6d7d8e158e",
    "ffconf.h": "202a7321066873fb3fa8c6ca83eba2b5964a091c366962f87ebd86332652430a",
    "ffunicode.c": "3f1632c1f1e64b0b683b0d7e51341b9870728f398604869dd8211f1819509a8e",
    "diskio.h": "1c2b29f53e061c55d43b2e412c3a61320b2621bac7561a05e275514baa44785a",
}
CONFIG = {
    "FF_USE_MKFS": 1,
    "FF_USE_LABEL": 1,
    "FF_USE_LFN": 2,
    "FF_LFN_UNICODE": 2,
    "FF_CODE_PAGE": 437,
    "FF_MAX_SS": 4096,
    "FF_FS_NORTC": 1,
    "FF_NORTC_YEAR": 2000,
}
CASES = [
    ("fat12", 2880, 512, 12),
    ("fat16", 16384, 512, 16),
    ("fat32", 131072, 512, 32),
    ("fat16-sector4096", 8192, 4096, 16),
]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def payloads() -> dict[str, bytes]:
    return {
        "HELLO.TXT": b"CrispCloud independent FAT reference.\n",
        "café-雪.txt": "Unicode FAT payload: café and 雪.\n".encode(),
        "empty.bin": b"",
        "nested/payload.bin": bytes((i * 37 + 11) & 255 for i in range(8193)),
        "nested/Long Unicode name 雪 beyond thirteen.txt": b"Multiple VFAT name records.\n",
        "emoji-😀.txt": b"UTF-16 surrogate-pair long name.\n",
        "abcdefghijklm": b"Exactly thirteen UTF-16 name units.\n",
        "fragmented.bin": bytes((i * 19 + i // 13 + 7) & 255 for i in range(4099)),
        "blocker.bin": bytes((i * 5 + 91) & 255 for i in range(4096)),
    }


def gzip_bytes(data: bytes) -> bytes:
    # Fixed gzip header, no filename/time/platform field. Compression bytes are
    # additionally bound to the recorded fixture identity and zlib version.
    codec = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed = codec.compress(data) + codec.flush()
    return bytes.fromhex("1f8b08000000000002ff") + packed + struct.pack(
        "<II", zlib.crc32(data), len(data) & 0xFFFFFFFF
    )


def geometry(image: bytes) -> dict:
    u16 = lambda at: int.from_bytes(image[at : at + 2], "little")
    u32 = lambda at: int.from_bytes(image[at : at + 4], "little")
    sector = u16(11)
    cluster_sectors = image[13]
    reserved = u16(14)
    fats = image[16]
    root_entries = u16(17)
    total = u16(19) or u32(32)
    fat_sectors = u16(22) or u32(36)
    root_sectors = (root_entries * 32 + sector - 1) // sector
    data_sector = reserved + fats * fat_sectors + root_sectors
    clusters = (total - data_sector) // cluster_sectors
    bits = 12 if clusters < 4085 else 16 if clusters < 65525 else 32
    return {
        "fat_bits": bits,
        "sector_bytes": sector,
        "sectors_per_cluster": cluster_sectors,
        "reserved_sectors": reserved,
        "fat_copies": fats,
        "fat_sectors": fat_sectors,
        "root_entries": root_entries,
        "root_cluster": u32(44) if bits == 32 else None,
        "root_directory_offset": (reserved + fats * fat_sectors) * sector,
        "data_offset": data_sector * sector,
        "data_clusters": clusters,
        "total_sectors": total,
    }


def allocation_value(image: bytes, geom: dict, cluster: int, copy: int = 0) -> int:
    at = (geom["reserved_sectors"] + copy * geom["fat_sectors"]) * geom["sector_bytes"]
    bits = geom["fat_bits"]
    if bits == 12:
        at += cluster + cluster // 2
        value = int.from_bytes(image[at : at + 2], "little")
        return value >> 4 if cluster & 1 else value & 0xFFF
    at += cluster * (bits // 8)
    return int.from_bytes(image[at : at + bits // 8], "little") & (
        0x0FFFFFFF if bits == 32 else 0xFFFF
    )


def chain(image: bytes, geom: dict, first: int) -> list[int]:
    result = []
    current = first
    eof = {12: 0xFF8, 16: 0xFFF8, 32: 0x0FFFFFF8}[geom["fat_bits"]]
    while current < eof:
        assert 2 <= current < geom["data_clusters"] + 2
        assert current not in result and len(result) < 1000
        result.append(current)
        value = allocation_value(image, geom, current)
        for copy in range(1, geom["fat_copies"]):
            assert allocation_value(image, geom, current, copy) == value
        current = value
    return result


def cluster_offset(geom: dict, cluster: int) -> int:
    return geom["data_offset"] + (cluster - 2) * geom["sectors_per_cluster"] * geom["sector_bytes"]


def fragment_details(image: bytes, geom: dict) -> dict:
    if geom["fat_bits"] == 32:
        root = b"".join(
            image[cluster_offset(geom, c) : cluster_offset(geom, c) + geom["sector_bytes"]]
            for c in chain(image, geom, geom["root_cluster"])
        )
    else:
        at = geom["root_directory_offset"]
        root = image[at : at + geom["root_entries"] * 32]
    entries = [root[i : i + 32] for i in range(0, len(root), 32)]
    entry = next(e for e in entries if e[:6] == b"FRAGME" and e[8:11] == b"BIN")
    first = int.from_bytes(entry[26:28], "little") | int.from_bytes(entry[20:22], "little") << 16
    clusters = chain(image, geom, first)
    assert any(b != a + 1 for a, b in zip(clusters, clusters[1:])), clusters
    return {"first_cluster": first, "cluster_chain": clusters, "noncontiguous": True}


def nonzero_ranges(image: bytes) -> list[tuple[int, bytes]]:
    # Lossless sparse encoding of externally mastered bytes. The logical image
    # length and full SHA256 remain authoritative; omitted sectors are all zero.
    result = []
    start = None
    for at in range(0, len(image), 512):
        nonzero = any(image[at : at + 512])
        if start is not None and (not nonzero or at - start >= 65536):
            result.append((start, image[start:at]))
            start = None
        if nonzero and start is None:
            start = at
    if start is not None:
        result.append((start, image[start:]))
    assert all(length > 0 for _, data in result for length in [len(data)])
    return result


def dart_file(images: list[dict], expected: dict[str, bytes]) -> str:
    lines = [
        "// Generated by generate_fat_reference.py; see fat-reference-manifest.json.",
        "// Original payloads and lossless fixture encoding: SPDX-License-Identifier: MIT.",
        "import 'dart:convert';",
        "import 'dart:typed_data';",
        "",
        "import 'package:archive/archive.dart' as archive;",
        "import 'package:koni_archive/koni_archive.dart' as koni;",
        "",
        "class FatReferenceImageData {",
        "  const FatReferenceImageData(this.length, this.sha256, this.fatBits, this.sectorBytes, this.ranges);",
        "  final int length, fatBits, sectorBytes;",
        "  final String sha256;",
        "  final List<(int, String)> ranges;",
        "}",
        "",
        "const fatReferenceImages = <String, FatReferenceImageData>{",
    ]
    for data in images:
        lines.extend([
            f"  '{data['name']}': FatReferenceImageData(",
            f"    {data['bytes']}, '{data['sha256']}', {data['geometry']['fat_bits']}, {data['geometry']['sector_bytes']}, [",
        ])
        for at, block in data["ranges"]:
            encoded = base64.b64encode(gzip_bytes(block)).decode()
            lines.append(f"      ({at},")
            for i in range(0, len(encoded), 100):
                lines.append("        '" + encoded[i : i + 100] + "'")
            lines.append("      ),")
        lines.append("    ]," )
        lines.append("  ),")
    lines.extend(["};", "", "const fatReferencePayloads = <String, String>{"])
    for name, contents in expected.items():
        lines.append(f"  '{name}': '{sha(contents)}',")
    lines.extend([
        "};", "", "const fatReferenceDirectories = <String>['nested', 'empty-dir'];", "",
        "List<(int, Uint8List)> fatReferenceRanges(String name) => [",
        "  for (final range in fatReferenceImages[name]!.ranges)",
        "    (range.$1, Uint8List.fromList(archive.GZipDecoder().decodeBytes(base64Decode(range.$2)))),",
        "];", "",
        "Uint8List fatReferenceBytes(String name) {",
        "  final bytes = Uint8List(fatReferenceImages[name]!.length);",
        "  for (final (offset, data) in fatReferenceRanges(name)) {",
        "    bytes.setRange(offset, offset + data.length, data);",
        "  }",
        "  return bytes;",
        "}", "",
        "/// Lossless positional view of a fully mastered external reference image.",
        "class FatReferenceSource implements koni.ByteSource {",
        "  FatReferenceSource(this.fixtureName) : blocks = fatReferenceRanges(fixtureName);",
        "  final String fixtureName;",
        "  final List<(int, Uint8List)> blocks;",
        "  final rangesRead = <(int, int)>[];",
        "  bool closed = false;",
        "  int closeCount = 0, largestRequest = 0, requestedBytes = 0;",
        "  @override",
        "  int get length => fatReferenceImages[fixtureName]!.length;",
        "  @override",
        "  String get name => '$fixtureName.img';",
        "  @override",
        "  Future<Uint8List> read(int offset, int count) async {",
        "    if (closed) throw StateError('Read after close');",
        "    if (offset < 0 || count < 0 || offset > length - count) {",
        "      throw RangeError('Read outside mastered image');",
        "    }",
        "    rangesRead.add((offset, count));",
        "    requestedBytes += count;",
        "    if (count > largestRequest) largestRequest = count;",
        "    final out = Uint8List(count);",
        "    for (final (at, data) in blocks) {",
        "      final start = offset > at ? offset : at;",
        "      final end = offset + count < at + data.length ? offset + count : at + data.length;",
        "      if (end > start) out.setRange(start - offset, end - offset, data, start - at);",
        "    }",
        "    return out;",
        "  }",
        "  @override",
        "  Future<void> close() async { closed = true; closeCount++; }",
        "}", "",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fatfs-zip", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--dart", default="dart", help="Dart formatter from the qualified app SDK")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    archive_bytes = args.fatfs_zip.read_bytes()
    if sha(archive_bytes) != UPSTREAM_SHA256:
        raise SystemExit("FatFs archive SHA256 differs from the pinned reference")
    output = args.output_dir.resolve()
    build = output / "build"
    build.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as source:
        for name, digest in UPSTREAM_FILES.items():
            contents = source.read("source/" + name)
            assert sha(contents) == digest, name
            (build / name).write_bytes(contents)
    config = (build / "ffconf.h").read_text()
    for name, value in CONFIG.items():
        config, count = re.subn(rf"(#define\s+{name}\s+)\d+", rf"\g<1>{value}", config)
        assert count == 1, name
    (build / "ffconf.h").write_text(config)
    helper = ROOT / "test/support/fat_reference_helper.c"
    executable = build / "fat_reference_helper"
    command = [args.cc, "-std=c99", "-O2", "-I", str(build), str(helper),
               str(build / "ff.c"), str(build / "ffunicode.c"), "-o", str(executable)]
    subprocess.run(command, check=True)
    expected = payloads()
    payload_dir = output / "payloads"
    for name, data in expected.items():
        target = payload_dir / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    images = []
    for name, sectors, sector_bytes, bits in CASES:
        target = output / (name + ".img")
        invocation = [str(executable), str(target), str(sectors), str(sector_bytes), str(bits), str(payload_dir)]
        completed = subprocess.run(invocation, capture_output=True, text=True)
        if completed.returncode:
            raise RuntimeError(f"FatFs helper failed for {name}: {completed.stderr}")
        image = target.read_bytes()
        geom = geometry(image)
        assert geom["fat_bits"] == bits and geom["sector_bytes"] == sector_bytes
        images.append({"name": name, "bytes": len(image), "sha256": sha(image),
                       "geometry": geom, "fragmented_file": fragment_details(image, geom),
                       "ranges": nonzero_ranges(image)})
        print(json.dumps({"name": name, "image_sha256": sha(image), "geometry": geom,
                          "writer": json.loads(completed.stdout)}, ensure_ascii=False))
    manifest = {
        "schema": 1,
        "writer": {"name": "ChaN FatFs", "version": "R0.16", "url": UPSTREAM_URL,
                   "archive_sha256": UPSTREAM_SHA256, "source_sha256": UPSTREAM_FILES,
                   "license": "Upstream FatFs BSD-style, equivalent to BSD-1-Clause",
                   "license_url": "https://elm-chan.org/fsw/ff/doc/appnote.html#license",
                   "runtime_dependency": False, "config_overrides": CONFIG,
                   "configured_ffconf_sha256": sha((build / "ffconf.h").read_bytes()),
                   "host_helper_sha256": sha(helper.read_bytes())},
        "payload_origin": "Original deterministic CrispCloud test content; MIT.",
        "directories": ["nested", "empty-dir"],
        "files": {name: {"bytes": len(data), "sha256": sha(data)} for name, data in expected.items()},
        "images": [{k: v for k, v in image.items() if k != "ranges"} | {
            "encoding": "Exact nonzero 512-byte sector runs; all omitted bytes are zero.",
            "stored_ranges": [{"offset": at, "bytes": len(data), "sha256": sha(data)} for at, data in image["ranges"]]
        } for image in images],
        "normalization": "None: fixed clock/configuration in the writer; output image bytes are not patched.",
    }
    dart = ROOT / "test/support/archive_fat_reference_data.dart"
    json_path = ROOT / "test/fixtures/archives/fat-reference-manifest.json"
    formatted = build / "generated_fat_reference.dart"
    formatted.write_text(dart_file(images, expected))
    subprocess.run([args.dart, "format", str(formatted)], check=True)
    products = {dart: formatted.read_text(), json_path: json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"}
    for target, contents in products.items():
        if args.check:
            assert target.read_text() == contents, f"Generated file differs: {target}"
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(contents)
    print(json.dumps({"check": args.check, "generated_files": {str(p.relative_to(ROOT)): sha(s.encode()) for p, s in products.items()}}))


if __name__ == "__main__":
    main()
