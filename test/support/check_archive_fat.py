#!/usr/bin/env python3
"""Extract exact committed FAT references with an independently supplied 7-Zip.

The external executable and extracted images stay outside the application.
The complete externally mastered image bytes are reconstructed from the Dart
fixture's lossless sparse encoding before any external program reads them.
"""

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 CrispCloud contributors

from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_reference_images(root: Path) -> tuple[dict, Path, dict[str, bytes]]:
    """Decode all committed images, checking each range and full image hash."""
    manifest_path = root / "test/fixtures/archives/fat-reference-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    dart_path = root / "test/support/archive_fat_reference_data.dart"
    source = dart_path.read_text().split("const fatReferenceImages", 1)[1].split("};", 1)[0]
    image_pattern = re.compile(
        r"'([^']+)':\s*FatReferenceImageData\(\s*(\d+),\s*"
        r"'([0-9a-f]{64})',\s*(\d+),\s*(\d+),\s*\[(.*?)\],\s*\),",
        re.S,
    )
    range_pattern = re.compile(
        r"\(\s*(\d+),\s*((?:'[A-Za-z0-9+/=]+'\s*)+),?\s*\)", re.S
    )
    expected_images = {row["name"]: row for row in manifest["images"]}
    fixtures = {}
    for match in image_pattern.finditer(source):
        name, length_text, digest, fat_text, sector_text, body = match.groups()
        if name in fixtures or name not in expected_images:
            raise ValueError("Duplicate or unexpected image: " + name)
        expected = expected_images[name]
        if (
            int(length_text) != expected["bytes"]
            or digest != expected["sha256"]
            or int(fat_text) != expected["geometry"]["fat_bits"]
            or int(sector_text) != expected["geometry"]["sector_bytes"]
        ):
            raise ValueError("Embedded fixture header differs from manifest: " + name)
        image = bytearray(int(length_text))
        ranges = []
        previous_end = 0
        for range_match in range_pattern.finditer(body):
            at = int(range_match.group(1))
            encoded = "".join(re.findall(r"'([^']*)'", range_match.group(2)))
            block = gzip.decompress(base64.b64decode(encoded, validate=True))
            if (
                not block
                or at < previous_end
                or at % 512
                or len(block) % 512
                or at + len(block) > len(image)
            ):
                raise ValueError("Invalid sparse fixture range: " + name)
            image[at : at + len(block)] = block
            previous_end = at + len(block)
            ranges.append({"offset": at, "bytes": len(block), "sha256": sha(block)})
        if ranges != expected["stored_ranges"] or sha(image) != digest:
            raise ValueError("Committed image bytes differ from manifest: " + name)
        fixtures[name] = bytes(image)
    if set(fixtures) != set(expected_images):
        raise ValueError("Committed fixture inventory differs from manifest")
    return manifest, dart_path, fixtures


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sevenzip", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    manifest, dart_path, fixtures = read_reference_images(root)
    binary = args.sevenzip.resolve()
    version_run = subprocess.run([str(binary), "i"], capture_output=True, text=True, check=True)
    version = next(
        line.strip() for line in version_run.stdout.splitlines() if line.startswith("7-Zip")
    )
    report = {
        "schema": 1,
        "scope": "Complete physical extraction of four externally mastered reference volumes.",
        "oracle": {
            "name": "7-Zip",
            "binary_sha256": sha(binary.read_bytes()),
            "version": version,
            "runtime_dependency": False,
        },
        "script_sha256": sha(Path(__file__).read_bytes()),
        "fixture_source_sha256": sha(dart_path.read_bytes()),
        "fixture_manifest_sha256": sha(
            (root / "test/fixtures/archives/fat-reference-manifest.json").read_bytes()
        ),
        "cases": [],
        "passed": 0,
    }
    args.work_dir.mkdir(parents=True, exist_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix="crisp-fat-oracle-", dir=args.work_dir) as temporary:
            work = Path(temporary)
            for name, data in fixtures.items():
                image = work / (name + ".img")
                image.write_bytes(data)
                extracted = work / (name + "-extracted")
                run = subprocess.run(
                    [str(binary), "x", "-y", "-o" + str(extracted), str(image)],
                    capture_output=True,
                    text=True,
                )
                row = {
                    "name": name,
                    "image_bytes": len(data),
                    "image_sha256": sha(data),
                    "exit_code": run.returncode,
                    "stdout": run.stdout,
                    "stderr": run.stderr,
                    "files": {},
                    "directories": [],
                }
                report["cases"].append(row)
                if run.returncode != 0:
                    raise ValueError("Independent extraction failed: " + name)
                for path in sorted(extracted.rglob("*")):
                    if path.is_symlink():
                        raise ValueError("Unexpected symlink in reference extraction")
                    relative = path.relative_to(extracted).as_posix()
                    if path.is_file():
                        content = path.read_bytes()
                        row["files"][relative] = {"bytes": len(content), "sha256": sha(content)}
                    elif path.is_dir():
                        row["directories"].append(relative)
                    else:
                        raise ValueError("Unexpected filesystem node in extraction")
                if row["files"] != manifest["files"]:
                    raise ValueError("Independent extraction contents differ: " + name)
                if sorted(row["directories"]) != sorted(manifest["directories"]):
                    raise ValueError("Independent extraction directories differ: " + name)
                row["image_sha256_after_extraction"] = sha(image.read_bytes())
                if row["image_sha256_after_extraction"] != row["image_sha256"]:
                    raise ValueError("External extractor changed reference image: " + name)
                row["exact_payloads_match"] = True
                row["exact_directories_match"] = True
                report["passed"] += 1
    finally:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(
        json.dumps(
            {
                "passed": report["passed"],
                "files_per_image": len(manifest["files"]),
                "directories_per_image": len(manifest["directories"]),
                "oracle_binary_sha256": report["oracle"]["binary_sha256"],
            }
        )
    )


if __name__ == "__main__":
    main()
