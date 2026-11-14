#!/usr/bin/env python3
"""Master and independently extract reproducible ext reference images.

Copyright (c) 2026 CrispCloud contributors. SPDX-License-Identifier: MIT.

The externally supplied e2fsprogs executables are qualification tools only.
They are never linked, bundled, or invoked by the app. This script retains
original payloads and filesystem bytes produced by mke2fs/debugfs, not their
source. e2fsck checks complete images without modifying them; debugfs dumps
every regular payload independently of the Dart reader.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[2]
EPOCH = 946684800
HASH_SEED = "11223344-5566-7788-99aa-bbccddeeff00"
CONFIG = "[defaults]\nbase_features = none\ninode_ratio = 16384\nenable_periodic_fsck = 0\n"
COMMON_FEATURES = "filetype,sparse_super,large_file,resize_inode,dir_index,ext_attr"
EXT4_FEATURES = COMMON_FEATURES + ",has_journal,extent,64bit,flex_bg,metadata_csum,huge_file,dir_nlink,extra_isize"
CASES = [
    ("ext2", "ext2", 8 * 1024 * 1024, 1024, 128, COMMON_FEATURES),
    ("ext3", "ext3", 16 * 1024 * 1024, 2048, 256, COMMON_FEATURES + ",has_journal"),
    ("ext4", "ext4", 32 * 1024 * 1024, 4096, 256, EXT4_FEATURES + ",metadata_csum_seed"),
    ("ext4-uuid", "ext4", 16 * 1024 * 1024, 1024, 256, EXT4_FEATURES),
]
DIRECTORIES = ["lost+found", "nested", "empty-dir"]
SPECIALS = ["hello-link", "long-link", "named-pipe"]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def payloads() -> dict[str, bytes]:
    sparse = bytearray(16 * 4096 + 57)
    for island in range(9):
        at = island * 8192
        count = min(4096, len(sparse) - at)
        sparse[at : at + count] = bytes([65 + island]) * count
    return {
        "hello.txt": b"Hello from ext filesystem\n",
        "nested/café-雪.txt": "Unicode ext payload: café and 雪.\n".encode(),
        "emoji-😀.txt": b"UTF-8 supplementary-plane filename.\n",
        "empty.bin": b"",
        "nested/payload.bin": bytes((i * 37 + 11) & 255 for i in range(8193)),
        "nested/long-name-beyond-a-single-directory-word.txt": b"Original nested reference payload.\n",
        "indirect.bin": bytes((i * 19 + i // 13 + 7) & 255 for i in range(1100003)),
        "sparse.bin": bytes(sparse),
    }


def run(command: list[str], env: dict[str, str]) -> str:
    result = subprocess.run(command, env=env, capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


def quote(value: str) -> str:
    if any(char in value for char in ('"', "\\", "\n", "\r")):
        raise ValueError("Unsupported fixture command path")
    return '"' + value + '"'


def gzip_bytes(data: bytes) -> bytes:
    codec = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed = codec.compress(data) + codec.flush()
    return bytes.fromhex("1f8b08000000000002ff") + packed + struct.pack("<II", zlib.crc32(data), len(data) & 0xFFFFFFFF)


def nonzero_ranges(image: bytes) -> list[tuple[int, bytes]]:
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
    return result


def geometry(image: bytes) -> dict:
    block_size = 1024 << struct.unpack_from("<I", image, 1024 + 24)[0]
    u32 = lambda at: struct.unpack_from("<I", image, 1024 + at)[0]
    return {
        "block_bytes": block_size,
        "blocks": u32(4),
        "blocks_per_group": u32(32),
        "inodes": u32(0),
        "inodes_per_group": u32(40),
        "inode_bytes": struct.unpack_from("<H", image, 1024 + 88)[0],
        "features_compat": u32(92),
        "features_incompat": u32(96),
        "features_ro_compat": u32(100),
        "state": struct.unpack_from("<H", image, 1024 + 58)[0],
    }


def master(case: tuple, index: int, output: Path, tools: dict[str, Path], env: dict[str, str], expected: dict[str, bytes]) -> tuple[dict, dict]:
    name, kind, length, block_size, inode_size, features = case
    work = output / name
    work.mkdir(parents=True, exist_ok=True)
    image_path = output / (name + ".img")
    with image_path.open("wb") as image:
        image.truncate(length)
    uuid = f"10203040-5060-7080-90a0-b0c0d0e0f{index:03x}"
    command = [str(tools["mke2fs"]), "-q", "-F", "-t", kind, "-b", str(block_size), "-I", str(inode_size), "-g", "1024", "-N", "128", "-m", "0", "-U", uuid, "-L", "CRISP_EXT_REF", "-O", features, "-E", f"lazy_itable_init=0,lazy_journal_init=0,hash_seed={HASH_SEED},root_owner=0:0,nodiscard", str(image_path)]
    logs = {"master": run(command, env)}
    commands = ["mkdir /nested", "mkdir /empty-dir"]
    for number, (path, data) in enumerate(expected.items()):
        source = work / f"payload-{number:02d}.bin"
        source.write_bytes(data)
        source.chmod(0o644)
        os.utime(source, (EPOCH, EPOCH))
        commands.append(f"write {quote(str(source))} {quote('/' + path)}")
    commands.extend([
        "ln /hello.txt /hello-hardlink.txt",
        "sif /hello.txt links_count 2",
        "symlink /hello-link hello.txt",
        "symlink /long-link " + "nested/" * 12 + "payload.bin",
        "mknod named-pipe p",
    ])
    files = {**expected, "hello-hardlink.txt": expected["hello.txt"]}
    if kind == "ext4":
        empty = work / "empty.bin"
        empty.write_bytes(b"")
        commands.extend([f"write {quote(str(empty))} /unwritten.bin", "fallocate /unwritten.bin 0 5", "sif /unwritten.bin size 24593"])
        files["unwritten.bin"] = bytes(24593)
    paths = ["/", *DIRECTORIES, *files, *SPECIALS]
    for path in paths:
        target = quote("/" + path.lstrip("/"))
        for field, value in [("uid", 0), ("gid", 0), ("atime", EPOCH), ("ctime", EPOCH), ("mtime", EPOCH)]:
            commands.append(f"sif {target} {field} {value}")
        if inode_size > 128:
            commands.append(f"sif {target} crtime {EPOCH}")
    command_file = work / "populate.debugfs"
    command_file.write_text("\n".join(commands) + "\n")
    logs["populate"] = run([str(tools["debugfs"]), "-w", "-f", str(command_file), str(image_path)], env)
    image = image_path.read_bytes()
    before = sha(image)
    logs["fsck"] = run([str(tools["e2fsck"]), "-f", "-n", str(image_path)], env)
    records = {}
    for number, (path, data) in enumerate(files.items()):
        target = work / f"extracted-{number:02d}.bin"
        logs["extract-" + path] = run([str(tools["debugfs"]), "-R", f"dump {quote('/' + path)} {quote(str(target))}", str(image_path)], env)
        if target.read_bytes() != data:
            raise AssertionError("External extraction differs: " + name + ":" + path)
        stat = run([str(tools["debugfs"]), "-R", "stat " + quote('/' + path), str(image_path)], env)
        inode = re.search(r"Inode: (\d+)", stat)
        if inode is None:
            raise AssertionError("Missing inode metadata: " + path)
        records[path] = {"bytes": len(data), "sha256": sha(data), "inode": int(inode[1]), "stat": stat}
    if records["hello-hardlink.txt"]["inode"] != records["hello.txt"]["inode"]:
        raise AssertionError("Hardlink identity was not preserved")
    if kind != "ext4" and "(DIND)" not in records["indirect.bin"]["stat"]:
        raise AssertionError("Classic reference did not reach double indirection")
    if kind == "ext4" and "(ETB0)" not in records["sparse.bin"]["stat"]:
        raise AssertionError("External sparse reference did not create an extent node")
    if sha(image_path.read_bytes()) != before:
        raise AssertionError("Read-only external qualification changed the image")
    for label, log in logs.items():
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", label)
        (work / (safe + ".log")).write_text(log)
    record = {
        "name": name,
        "filesystem": kind,
        "bytes": length,
        "sha256": before,
        "uuid": uuid,
        "geometry": geometry(image),
        "mke2fs_arguments": command[1:-1] + ["<image>"],
        "files": records,
        "directories": DIRECTORIES,
        "special_entries": SPECIALS,
        "read_only_fsck_exit": 0,
        "external_extraction_matches": True,
        "source_unchanged_after_checks": True,
    }
    return record, {"record": record, "ranges": nonzero_ranges(image)}


def dart_file(images: list[dict]) -> str:
    lines = [
        "// Generated by generate_ext_reference.py; see ext-reference-manifest.json.",
        "// Original payloads and lossless fixture encoding: SPDX-License-Identifier: MIT.",
        "import 'dart:convert';",
        "import 'dart:typed_data';",
        "",
        "import 'package:archive/archive.dart' as archive;",
        "import 'package:koni_archive/koni_archive.dart' as koni;",
        "",
        "class ExtReferenceImageData {",
        "  const ExtReferenceImageData(this.length, this.sha256, this.blockBytes, this.ranges, this.files);",
        "  final int length, blockBytes;",
        "  final String sha256;",
        "  final List<(int, String)> ranges;",
        "  final Map<String, (int, String)> files;",
        "}",
        "",
        "const extReferenceImages = <String, ExtReferenceImageData>{",
    ]
    for data in images:
        record = data["record"]
        lines += [f"  '{record['name']}': ExtReferenceImageData(", f"    {record['bytes']}, '{record['sha256']}', {record['geometry']['block_bytes']}, ["]
        for at, block in data["ranges"]:
            encoded = base64.b64encode(gzip_bytes(block)).decode()
            lines.append(f"      ({at},")
            for i in range(0, len(encoded), 100):
                lines.append("        '" + encoded[i : i + 100] + "'")
            lines.append("      ),")
        lines += ["    ],", "    {"]
        for name, file in record["files"].items():
            lines.append(f"      '{name}': ({file['bytes']}, '{file['sha256']}'),")
        lines += ["    },", "  ),"]
    lines += ["};", "", "const extReferencePayloads = <String, String>{"]
    for name, data in {**payloads(), "hello-hardlink.txt": payloads()["hello.txt"]}.items():
        lines.append(f"  '{name}': '{sha(data)}',")
    lines += [
        "};", "",
        "const extReferenceDirectories = <String>['lost+found', 'nested', 'empty-dir'];",
        "const extReferenceSpecials = <String>['hello-link', 'long-link', 'named-pipe'];", "",
        "List<(int, Uint8List)> extReferenceRanges(String name) => [",
        "  for (final range in extReferenceImages[name]!.ranges)",
        "    (range.$1, Uint8List.fromList(const archive.GZipDecoder().decodeBytes(base64Decode(range.$2)))),",
        "];", "",
        "Uint8List extReferenceBytes(String name) {",
        "  final bytes = Uint8List(extReferenceImages[name]!.length);",
        "  for (final (offset, data) in extReferenceRanges(name)) {",
        "    bytes.setRange(offset, offset + data.length, data);",
        "  }",
        "  return bytes;",
        "}", "",
        "/// Lossless positional view of an externally mastered complete image.",
        "class ExtReferenceSource implements koni.ByteSource {",
        "  ExtReferenceSource(this.fixtureName) : blocks = extReferenceRanges(fixtureName);",
        "  final String fixtureName;",
        "  final List<(int, Uint8List)> blocks;",
        "  final rangesRead = <(int, int)>[];",
        "  bool closed = false;",
        "  int closeCount = 0, largestRequest = 0, requestedBytes = 0;",
        "  @override",
        "  int get length => extReferenceImages[fixtureName]!.length;",
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
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mke2fs", type=Path, required=True)
    parser.add_argument("--debugfs", type=Path, required=True)
    parser.add_argument("--e2fsck", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--tool-provenance", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    os.umask(0o022)
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    tools = {name: getattr(args, name).resolve() for name in ["mke2fs", "debugfs", "e2fsck"]}
    config = output / "mke2fs.conf"
    config.write_text(CONFIG)
    env = {**os.environ, "MKE2FS_CONFIG": str(config), "E2FSPROGS_FAKE_TIME": str(EPOCH), "SOURCE_DATE_EPOCH": str(EPOCH), "TZ": "UTC", "LC_ALL": "C.UTF-8"}
    expected = payloads()
    records, images = [], []
    for index, case in enumerate(CASES, 1):
        record, image = master(case, index, output, tools, env, expected)
        records.append(record)
        images.append(image)
    provenance = []
    if args.tool_provenance:
        provenance = [item for item in json.loads(args.tool_provenance.read_text()) if item.get("target") == "e2fsprogs"]
    manifest = {
        "schema": 1,
        "purpose": "External whole-image ext2/ext3/ext4 mastering, read-only consistency checking, and independent payload extraction.",
        "external_tools_only": True,
        "tool_source": "https://git.kernel.org/pub/scm/fs/ext2/e2fsprogs.git",
        "tools": {name: {"sha256": sha(path.read_bytes()), "version": run([str(path), "-V"], env).strip()} for name, path in tools.items()},
        "tool_packages": provenance,
        "fixed_epoch": EPOCH,
        "config": CONFIG,
        "config_sha256": sha(CONFIG.encode()),
        "hash_seed": HASH_SEED,
        "filesystem_bytes_modified_after_external_mastering": False,
        "compression": {"method": "Fixed-header gzip over lossless nonzero 512-byte sectors, chunks at most 64KiB", "zlib": zlib.ZLIB_RUNTIME_VERSION},
        "images": records,
    }
    generated = output / "archive_ext_reference_data.dart"
    generated.write_text(dart_file(images))
    subprocess.run([args.dart, "format", str(generated)], check=True)
    manifest_path = output / "ext-reference-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    destinations = {
        generated: ROOT / "test/support/archive_ext_reference_data.dart",
        manifest_path: ROOT / "test/fixtures/archives/ext-reference-manifest.json",
    }
    for source, target in destinations.items():
        if args.check:
            if not target.is_file() or target.read_bytes() != source.read_bytes():
                raise SystemExit("Reference reproduction differs: " + target.name)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
    print(json.dumps({"images": len(records), "regular_file_instances": sum(len(record["files"]) for record in records), "special_entry_instances": len(records) * len(SPECIALS), "external_consistency_checks_passed": len(records), "reproduction_check": args.check, "image_sha256": {record["name"]: record["sha256"] for record in records}}))


if __name__ == "__main__":
    main()
