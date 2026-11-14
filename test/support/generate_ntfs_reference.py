#!/usr/bin/env python3
"""Master complete, reproducible NTFS 3.1 images with external ntfs-3g tools.

Copyright (c) 2026 CrispCloud contributors. SPDX-License-Identifier: MIT.

The separately supplied GPL tools, headers, and library are external test tools
only. No such executable or code is linked into, invoked by, or shipped with
the app. The original small C driver uses their public API; it never patches
filesystem bytes. Every regular unnamed payload and named stream is extracted
independently with ntfscat before the complete image is losslessly encoded.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = ROOT / "test/support"
EPOCH = 946684800
CASES = [
    ("ntfs31", 16 * 1024 * 1024, 512, 4096),
    ("ntfs31-small", 16 * 1024 * 1024, 512, 512),
    ("ntfs31-4k", 32 * 1024 * 1024, 4096, 4096),
    ("ntfs31-4k-attrlist", 32 * 1024 * 1024, 4096, 4096),
]
DIRECTORIES = ["nested", "nested/deeper", "empty-dir", "many"]
LONG_NAME = "nested/long-" + "café-雪-" * 12 + "tail.txt"
TOOL_LOCATIONS = {
    "mkntfs": "usr/sbin/mkntfs",
    "ntfslabel": "usr/sbin/ntfslabel",
    "ntfscat": "usr/bin/ntfscat",
    "ntfsls": "usr/bin/ntfsls",
    "ntfsinfo": "usr/bin/ntfsinfo",
    "ntfsfix": "usr/bin/ntfsfix",
    "ntfsresize": "usr/sbin/ntfsresize",
}
COMMAND_RECORDS: list[dict] = []


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def payloads() -> dict[str, bytes]:
    sparse = bytearray(96 * 1024 + 37)
    sparse[:100] = b"A" * 100
    sparse[32768:36864] = b"B" * 4096
    sparse[-37:] = b"C" * 37
    values = {
        "hello.txt": b"Hello from NTFS filesystem\n",
        "nested/café-雪.txt": "Unicode NTFS payload: café and 雪.\n".encode(),
        "emoji-😀.txt": b"Supplementary-plane NTFS filename.\n",
        "empty.bin": b"",
        "resident.bin": bytes(range(256)) + b"!",
        "nested/payload.bin": bytes((i * 37 + 11) & 255 for i in range(8193)),
        "nested/deeper/inside.txt": b"A nested directory entry.\n",
        LONG_NAME: b"Original long Unicode name payload.\n",
        "nonresident.bin": bytes((i * 19 + i // 13 + 7) & 255 for i in range(131075)),
        "sparse.bin": bytes(sparse),
        "fragmented.bin": bytes((i * 31 + 5) & 255 for i in range(32769)),
        "allocation-blocker.bin": bytes((i * 17 + 29) & 255 for i in range(32769)),
    }
    for index in range(48):
        name = f"many/item-{index:03d}-independent-directory-index-entry.txt"
        values[name] = f"External indexed-directory payload {index:03d}.\n".encode()
    return values


def streams() -> dict[str, dict[str, bytes]]:
    return {"hello.txt": {
        "notes-雪": "Named NTFS stream: notes and 雪.\n".encode(),
        "binary-😀": bytes((i * 13 + 3) & 255 for i in range(16387)),
    }}


def run(command: list[str], env: dict[str, str]) -> bytes:
    result = subprocess.run(command, env=env, capture_output=True, check=False)
    COMMAND_RECORDS.append({
        "argv": command, "exit_code": result.returncode,
        "stdout_bytes": len(result.stdout), "stdout_sha256": sha(result.stdout),
        "stderr_bytes": len(result.stderr), "stderr_sha256": sha(result.stderr),
    })
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command}\n"
                           + result.stdout.decode(errors="replace")
                           + result.stderr.decode(errors="replace"))
    return result.stdout


def tool_version(path: Path, env: dict[str, str]) -> dict:
    result = subprocess.run([str(path), "--version"], env=env, capture_output=True, check=False)
    output = (result.stdout + result.stderr).decode()
    version = next((line.strip() for line in output.splitlines() if "2022.10.3" in line), None)
    if version is None:
        raise AssertionError("Unexpected external tool version: " + str(path))
    return {"sha256": sha(path.read_bytes()), "version": version,
            "version_exit_code": result.returncode}


def gzip_bytes(data: bytes) -> bytes:
    codec = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed = codec.compress(data) + codec.flush()
    return bytes.fromhex("1f8b08000000000002ff") + packed + struct.pack("<II", zlib.crc32(data), len(data) & 0xFFFFFFFF)


def nonzero_ranges(image: bytes) -> list[tuple[int, bytes]]:
    result = []
    start = None
    for at in range(0, len(image), 512):
        nonzero = any(image[at:at + 512])
        if start is not None and (not nonzero or at - start >= 65536):
            result.append((start, image[start:at]))
            start = None
        if nonzero and start is None:
            start = at
    if start is not None:
        result.append((start, image[start:]))
    return result


def geometry(image: bytes) -> dict:
    sector = struct.unpack_from("<H", image, 11)[0]
    cluster = sector * image[13]
    encoded_record = struct.unpack_from("<b", image, 64)[0]
    encoded_index = struct.unpack_from("<b", image, 68)[0]
    return {
        "sector_bytes": sector,
        "cluster_bytes": cluster,
        "record_bytes": (1 << -encoded_record) if encoded_record < 0 else encoded_record * cluster,
        "index_bytes": (1 << -encoded_index) if encoded_index < 0 else encoded_index * cluster,
        "declared_sectors": struct.unpack_from("<Q", image, 40)[0],
        "mft_cluster": struct.unpack_from("<Q", image, 48)[0],
        "mirror_cluster": struct.unpack_from("<Q", image, 56)[0],
        "serial_hex": f"{struct.unpack_from('<Q', image, 72)[0]:016x}",
    }


def attribute_inventory(stat: str) -> list[dict]:
    result = []
    parts = re.split(r"Dumping attribute (\$[A-Z_]+) \((0x[0-9a-f]+)\) from mft record \d+ \(0x[0-9a-f]+\)\n", stat)
    for index in range(1, len(parts), 3):
        kind, kind_hex, text = parts[index:index + 3]
        record = {"type": kind, "type_code": int(kind_hex, 16)}
        name = re.search(r"Attribute name:\s+'(.*)'", text)
        record["name"] = name[1] if name else ""
        resident = re.search(r"Resident:\s+(Yes|No)", text)
        record["resident"] = resident is not None and resident[1] == "Yes"
        for label, key in [("Attribute flags", "flags"), ("Data size", "bytes"), ("Allocated size", "allocated_bytes"), ("Initialized size", "initialized_bytes"), ("Compressed size", "physical_bytes"), ("Compression unit", "compression_unit")]:
            match = re.search(re.escape(label) + r":\s+(0x[0-9a-f]+|\d+)", text)
            if match:
                record[key] = int(match[1], 0) if match[1].startswith("0x") else int(match[1])
        runs = []
        if "Runlist:" in text:
            for vcn, lcn, length in re.findall(r"^\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+|<HOLE>)\s+(0x[0-9a-f]+)\s*$", text, re.M):
                runs.append({"vcn": int(vcn, 16), "lcn": None if lcn == "<HOLE>" else int(lcn, 16), "clusters": int(length, 16)})
            record["runs"] = runs
        result.append(record)
    return result


def inode_stat(tools: dict[str, Path], env: dict[str, str], image: Path, work: Path, selector: list[str], label: str) -> dict:
    text = run([str(tools["ntfsinfo"]), "-v", *selector, str(image)], env).decode()
    (work / (label + ".log")).write_text(text)
    inode = re.search(r"Dumping Inode (\d+)", text)
    if not inode:
        raise AssertionError("No external inode stat: " + label)
    return {"record": int(inode[1]), "attributes": attribute_inventory(text), "ntfsinfo_sha256": sha(text.encode())}


def master(case: tuple, index: int, output: Path, tools: dict[str, Path], helper: Path, env: dict[str, str]) -> tuple[dict, dict]:
    name, length, sector, cluster = case
    work = output / name
    work.mkdir(parents=True, exist_ok=True)
    image = output / (name + ".img")
    with image.open("wb") as file:
        file.truncate(length)
    serial = f"1020304050607{index:03x}"
    format_args = ["-F", "-Q", "-T", "-c", str(cluster), "-s", str(sector), "-p", "0", "-H", "0", "-S", "0", "-L", "CRISP_NTFS_REF", str(image)]
    (work / "mkntfs.log").write_bytes(run([str(tools["mkntfs"]), *format_args], env))
    (work / "ntfslabel.log").write_bytes(run([str(tools["ntfslabel"]), "--new-serial=" + serial, str(image)], env))
    expected = payloads()
    if name == "ntfs31-4k":
        expected = {path: data for path, data in expected.items()
                    if not path.startswith("many/") or int(path[10:13]) < 8}
    sources = {}
    for number, (path, data) in enumerate(expected.items()):
        source = work / f"payload-{number:03d}.bin"
        source.write_bytes(data)
        os.utime(source, (EPOCH, EPOCH))
        sources[path] = source
    commands = [["mkdir", "/" + path] for path in DIRECTORIES]
    for path, source in sources.items():
        if path in ["fragmented.bin", "allocation-blocker.bin"]:
            continue
        commands.append(["sparse" if path == "sparse.bin" else "file", "/" + path, str(source)])
    commands += [
        ["fragmented", "/fragmented.bin", str(sources["fragmented.bin"]), "/allocation-blocker.bin", str(sources["allocation-blocker.bin"])],
        ["link", "/hello.txt", "/hello-hardlink.txt"],
    ]
    for path, data_streams in streams().items():
        for number, (stream_name, data) in enumerate(data_streams.items()):
            source = work / f"stream-{number}.bin"
            source.write_bytes(data)
            commands.append(["stream", "/" + path, stream_name, str(source)])
    script = work / "populate.tsv"
    script.write_text("\n".join("\t".join(command) for command in commands) + "\n")
    (work / "populate.log").write_bytes(run([str(helper), str(image), str(script)], env))
    complete = image.read_bytes()
    before = sha(complete)
    # These are the tools' documented checks, not a Windows chkdsk qualification.
    checks = {}
    for tool, args in [("ntfsfix", ["-n"]), ("ntfsresize", ["--info", "--no-action"]), ("ntfsls", ["-R", "-p", "/"]), ("ntfsinfo", ["-m"])]:
        log = run([str(tools[tool]), *args, str(image)], env)
        (work / (tool + ".log")).write_bytes(log)
        normalized = log.decode().replace(str(image), "<image>")
        checks[tool] = {"arguments": [*args, "<image>"], "exit_code": 0, "stdout": normalized}
    expected["hello-hardlink.txt"] = expected["hello.txt"]
    files = {}
    for number, (path, data) in enumerate(expected.items()):
        actual = run([str(tools["ntfscat"]), str(image), "/" + path], env)
        if actual != data:
            raise AssertionError("External unnamed payload mismatch: " + name + ":" + path)
        stat = inode_stat(tools, env, image, work, ["-F", "/" + path], f"file-{number:03d}")
        files[path] = {"bytes": len(data), "sha256": sha(data), "external_sha256": sha(actual), **stat}
    stream_records = {}
    for path, data_streams in streams().items():
        stream_records[path] = {}
        for stream_name, data in data_streams.items():
            actual = run([str(tools["ntfscat"]), "-n", stream_name, str(image), "/" + path], env)
            if actual != data:
                raise AssertionError("External named stream mismatch: " + stream_name)
            stream_records[path][stream_name] = {"bytes": len(data), "sha256": sha(data), "external_sha256": sha(actual)}
    dirs = {path: inode_stat(tools, env, image, work, ["-F", "/" + path], f"dir-{number}") for number, path in enumerate(["", *DIRECTORIES])}
    systems = {str(number): inode_stat(tools, env, image, work, ["-i", str(number)], f"system-{number:02d}") for number in [*range(12), 24, 25, 26]}
    all_records = [*files.values(), *dirs.values(), *systems.values()]
    has_attribute_list = any(a["type"] == "$ATTRIBUTE_LIST" for stat in all_records for a in stat["attributes"])
    if has_attribute_list != (name == "ntfs31-4k-attrlist"):
        raise AssertionError("Unexpected attribute-list profile in external fixture")
    if files["hello-hardlink.txt"]["record"] != files["hello.txt"]["record"]:
        raise AssertionError("External hardlink identity differs")
    data_attr = lambda path: next(a for a in files[path]["attributes"] if a["type"] == "$DATA" and not a["name"])
    if not data_attr("resident.bin")["resident"] or data_attr("nonresident.bin")["resident"]:
        raise AssertionError("Resident/nonresident coverage not mastered")
    if not any(run["lcn"] is None for run in data_attr("sparse.bin")["runs"]):
        raise AssertionError("Sparse data contains no real hole")
    if cluster >= 4096 and len(data_attr("fragmented.bin")["runs"]) < 5:
        raise AssertionError("Interleaving did not create real fragmentation")
    many_indexes = [a for a in dirs["many"]["attributes"] if a["type"] == "$INDEX_ALLOCATION"]
    if sector == 512 and (not many_indexes or many_indexes[0]["bytes"] <= 4096):
        raise AssertionError("External many directory did not split into multiple INDX blocks")
    if sha(image.read_bytes()) != before:
        raise AssertionError("External read-only qualification changed source bytes")
    record = {
        "name": name, "filesystem": "NTFS 3.1", "bytes": length, "sha256": before,
        "geometry": geometry(complete), "mkntfs_arguments": [*format_args[:-1], "<image>"],
        "fixed_serial": serial, "files": files, "named_streams": stream_records,
        "directories": dirs, "system_records": systems, "external_checks": checks,
        "supported_profile": not has_attribute_list,
        "unsupported_reason": "directory ATTRIBUTE_LIST" if has_attribute_list else None,
        "external_extraction_matches": True, "source_unchanged_after_checks": True,
    }
    return record, {"record": record, "ranges": nonzero_ranges(complete)}


def dart_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def dart_file(images: list[dict]) -> str:
    lines = [
        "// Generated by generate_ntfs_reference.py; see ntfs-reference-manifest.json.",
        "// Original payloads and lossless fixture encoding: SPDX-License-Identifier: MIT.",
        "import 'dart:convert';", "import 'dart:typed_data';", "",
        "import 'package:archive/archive.dart' as archive;",
        "import 'package:koni_archive/koni_archive.dart' as koni;", "",
        "class NtfsReferenceImageData {",
        "  const NtfsReferenceImageData(this.length, this.sha256, this.sectorBytes, this.clusterBytes, this.recordBytes, this.indexBytes, this.ranges, this.files, this.records);",
        "  final int length, sectorBytes, clusterBytes, recordBytes, indexBytes;",
        "  final String sha256;",
        "  final List<(int, String)> ranges;",
        "  final Map<String, (int, String)> files;",
        "  final Map<String, int> records;",
        "}", "", "const ntfsAllReferenceImages = <String, NtfsReferenceImageData>{",
    ]
    for data in images:
        record, geo = data["record"], data["record"]["geometry"]
        lines += [f"  {dart_string(record['name'])}: NtfsReferenceImageData(", f"    {record['bytes']}, '{record['sha256']}', {geo['sector_bytes']}, {geo['cluster_bytes']}, {geo['record_bytes']}, {geo['index_bytes']}, ["]
        for at, block in data["ranges"]:
            encoded = base64.b64encode(gzip_bytes(block)).decode()
            lines.append(f"      ({at},")
            for index in range(0, len(encoded), 100):
                lines.append("        '" + encoded[index:index + 100] + "'")
            lines.append("      ),")
        lines += ["    ],", "    {"]
        for path, file in record["files"].items():
            lines.append(f"      {dart_string(path)}: ({file['bytes']}, '{file['sha256']}'),")
        lines += ["    },", "    {"]
        for path, stat in {**record["directories"], **record["files"]}.items():
            lines.append(f"      {dart_string(path)}: {stat['record']},")
        lines += ["    },", "  ),"]
    lines += ["};", "",
              "final ntfsReferenceImages = <String, NtfsReferenceImageData>{",
              "  for (final entry in ntfsAllReferenceImages.entries)",
              "    if (!entry.key.endsWith('-attrlist')) entry.key: entry.value,",
              "};", "",
              "final ntfsUnsupportedReferenceImages = <String, NtfsReferenceImageData>{",
              "  'ntfs31-4k-attrlist': ntfsAllReferenceImages['ntfs31-4k-attrlist']!,",
              "};", "", "const ntfsReferencePayloads = <String, String>{"]
    for path, data in {**payloads(), "hello-hardlink.txt": payloads()["hello.txt"]}.items():
        lines.append(f"  {dart_string(path)}: '{sha(data)}',")
    lines += ["};", "", "const ntfsReferenceDirectories = <String>["]
    lines += [f"  {dart_string(path)}," for path in DIRECTORIES]
    lines += [" ];", "", "const ntfsReferenceStreams = <String, Map<String, (int, String)>>{"]
    for path, data_streams in streams().items():
        lines.append(f"  {dart_string(path)}: {{")
        for name, data in data_streams.items():
            lines.append(f"    {dart_string(name)}: ({len(data)}, '{sha(data)}'),")
        lines.append("  },")
    lines += [
        "};", "",
        "List<(int, Uint8List)> ntfsReferenceRanges(String name) => [",
        "  for (final range in ntfsAllReferenceImages[name]!.ranges)",
        "    (range.$1, Uint8List.fromList(const archive.GZipDecoder().decodeBytes(base64Decode(range.$2)))),",
        "];", "",
        "Uint8List ntfsReferenceBytes(String name) {",
        "  final bytes = Uint8List(ntfsAllReferenceImages[name]!.length);",
        "  for (final (offset, data) in ntfsReferenceRanges(name)) {",
        "    bytes.setRange(offset, offset + data.length, data);",
        "  }",
        "  return bytes;", "}", "",
        "/// Lossless positional view of an independently mastered whole image.",
        "class NtfsReferenceSource implements koni.ByteSource {",
        "  NtfsReferenceSource(this.fixtureName) : blocks = ntfsReferenceRanges(fixtureName);",
        "  final String fixtureName;",
        "  final List<(int, Uint8List)> blocks;",
        "  final rangesRead = <(int, int)>[];",
        "  bool closed = false;",
        "  int closeCount = 0, largestRequest = 0, requestedBytes = 0;",
        "  @override", "  int get length => ntfsAllReferenceImages[fixtureName]!.length;",
        "  @override", "  String get name => '$fixtureName.img';",
        "  @override", "  Future<Uint8List> read(int offset, int count) async {",
        "    if (closed) throw StateError('Read after close');",
        "    if (offset < 0 || count < 0 || offset > length - count) {",
        "      throw RangeError('Read outside mastered image');", "    }",
        "    rangesRead.add((offset, count));", "    requestedBytes += count;",
        "    if (count > largestRequest) largestRequest = count;",
        "    final out = Uint8List(count);",
        "    for (final (at, data) in blocks) {",
        "      final start = offset > at ? offset : at;",
        "      final end = offset + count < at + data.length ? offset + count : at + data.length;",
        "      if (end > start) {",
        "        out.setRange(start - offset, end - offset, data, start - at);",
        "      }",
        "    }", "    return out;", "  }", "  @override",
        "  Future<void> close() async { closed = true; closeCount++; }", "}", "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--tool-provenance", type=Path, required=True)
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    os.umask(0o022)
    output, tools_root = args.output_dir.resolve(), args.tools_root.resolve()
    output.mkdir(parents=True, exist_ok=True)
    tools = {name: tools_root / path for name, path in TOOL_LOCATIONS.items()}
    libraries = tools_root / "usr/lib/x86_64-linux-gnu"
    env = {**os.environ, "LD_LIBRARY_PATH": str(libraries), "LC_ALL": "C.UTF-8", "TZ": "UTC", "SOURCE_DATE_EPOCH": str(EPOCH)}
    helper, time_shim = output / "ntfs-reference-tool", output / "ntfs-reference-fixed-time.so"
    cc = str(Path(shutil.which(args.cc) or args.cc).resolve())
    build_commands = [
        [cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-Wl,--build-id=none", "-I" + str(tools_root / "usr/include"), str(SUPPORT / "ntfs_reference_tool.c"), "-L" + str(libraries), "-lntfs-3g", "-o", str(helper)],
        [cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC", "-Wl,--build-id=none", str(SUPPORT / "ntfs_reference_fixed_time.c"), "-ldl", "-o", str(time_shim)],
    ]
    for command in build_commands:
        run(command, env)
    env["LD_PRELOAD"] = str(time_shim)
    records, images = [], []
    for index, case in enumerate(CASES, 1):
        record, image = master(case, index, output, tools, helper, env)
        records.append(record)
        images.append(image)
    headers = tools_root / "usr/include/ntfs-3g"
    manifest = {
        "schema": 1,
        "purpose": "External complete-image NTFS 3.1 mastering, read-only consistency checks, and independent unnamed/named stream extraction.",
        "external_tools_only": True,
        "tool_source": "https://github.com/tuxera/ntfs-3g/tree/2022.10.3",
        "tools": {name: tool_version(path, env) for name, path in tools.items()},
        "tool_packages": json.loads(args.tool_provenance.read_text())["packages"],
        "external_library_sha256": sha((libraries / "libntfs-3g.so.89.0.0").read_bytes()),
        "external_header_sha256": {str(path.relative_to(headers)): sha(path.read_bytes()) for path in sorted(headers.glob("*.h"))},
        "compiler": {"version": run([cc, "--version"], env).decode().strip(), "sha256": sha(Path(cc).read_bytes())},
        "original_helper_source_sha256": sha((SUPPORT / "ntfs_reference_tool.c").read_bytes()),
        "original_time_shim_source_sha256": sha((SUPPORT / "ntfs_reference_fixed_time.c").read_bytes()),
        "helper_executable_sha256": sha(helper.read_bytes()),
        "time_shim_executable_sha256": sha(time_shim.read_bytes()),
        "fixed_payload_epoch": EPOCH,
        "format_time": "mkntfs --zero-time (1970-01-01T00:00:00Z)",
        "fixed_locale": "C.UTF-8",
        "filesystem_bytes_patched_by_generator": False,
        "external_version_scope": "NTFS 3.1 only; mkntfs has no NTFS 3.0 producer switch.",
        "compression": {"method": "Lossless nonzero 512-byte sectors in fixed-header gzip chunks of at most 64KiB", "zlib": zlib.ZLIB_RUNTIME_VERSION},
        "images": records,
    }
    receipt = {
        "environment": {key: env[key] for key in ["LD_LIBRARY_PATH", "LD_PRELOAD", "LC_ALL", "TZ", "SOURCE_DATE_EPOCH"]},
        "commands": COMMAND_RECORDS,
    }
    (output / "external-command-receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    generated = output / "archive_ntfs_reference_data.dart"
    generated.write_text(dart_file(images))
    subprocess.run([args.dart, "format", str(generated)], check=True)
    manifest_path = output / "ntfs-reference-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    destinations = {
        generated: SUPPORT / "archive_ntfs_reference_data.dart",
        manifest_path: ROOT / "test/fixtures/archives/ntfs-reference-manifest.json",
    }
    for source, target in destinations.items():
        if args.check:
            if not target.is_file() or target.read_bytes() != source.read_bytes():
                raise SystemExit("Reference reproduction differs: " + target.name)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
    print(json.dumps({"images": len(records), "regular_file_instances": sum(len(record["files"]) for record in records), "named_stream_instances": sum(len(data_streams) for record in records for data_streams in record["named_streams"].values()), "external_checks_passed": len(records), "reproduction_check": args.check, "image_sha256": {record["name"]: record["sha256"] for record in records}}))


if __name__ == "__main__":
    main()
