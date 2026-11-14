#!/usr/bin/env python3
"""Independently extract the committed UDF references with an external 7-Zip.

The executable remains outside the repository/application. This validates the
actual reference image bytes embedded in the portable Dart driver, not newly
constructed fixtures that could accidentally differ from the tested inputs.
"""

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 CrispCloud contributors

import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_reference_images(root):
    """Decode exact embedded fixture bytes and verify their fixed manifest."""
    manifest = json.loads((root / "test/fixtures/archives/udf-reference-manifest.json").read_text())
    dart_path = root / "test/support/archive_udf_reference_data.dart"
    source = dart_path.read_text().split("const udfReferenceImages", 1)[1].split("};", 1)[0]
    fixtures = {}
    for match in re.finditer(r"'([^']+)':\s*((?:'[^']*'\s*)+),", source):
        encoded = "".join(re.findall(r"'([^']*)'", match.group(2)))
        fixtures[match.group(1)] = gzip.decompress(base64.b64decode(encoded, validate=True))
    if set(fixtures) != set(manifest["fixtures"]):
        raise SystemExit("Committed fixture inventory differs from manifest")
    for name, data in fixtures.items():
        expected = manifest["fixtures"][name]
        if len(data) != expected["bytes"] or sha(data) != expected["sha256"]:
            raise SystemExit("Committed image bytes differ from manifest: " + name)
    return manifest, dart_path, fixtures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sevenzip", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    manifest, dart_path, fixtures = read_reference_images(root)
    binary = args.sevenzip.resolve()
    report = {"schema": 1, "oracle": {"binary_sha256": sha(binary.read_bytes()), "version": subprocess.check_output([str(binary), "i"], text=True).splitlines()[1].strip()}, "fixture_source_sha256": sha(dart_path.read_bytes()), "cases": []}
    with tempfile.TemporaryDirectory(prefix="crisp-udf-oracle-") as temporary:
        work = Path(temporary)
        for name, data in fixtures.items():
            expected_image = manifest["fixtures"][name]
            if len(data) != expected_image["bytes"] or sha(data) != expected_image["sha256"]:
                raise SystemExit("Committed image bytes differ from manifest: " + name)
            image = work / (name + ".iso")
            image.write_bytes(data)
            extracted = work / (name + "-extracted")
            run = subprocess.run([str(binary), "x", "-y", "-o" + str(extracted), str(image)], capture_output=True, text=True)
            row = {"name": name, "image_sha256": sha(data), "exit_code": run.returncode, "stdout": run.stdout, "stderr": run.stderr, "files": {}}
            if run.returncode != 0:
                report["cases"].append(row)
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
                raise SystemExit("Independent extraction failed: " + name)
            for path in extracted.rglob("*"):
                if path.is_symlink():
                    raise SystemExit("Unexpected symlink in reference extraction")
                if path.is_file():
                    content = path.read_bytes()
                    row["files"][path.relative_to(extracted).as_posix()] = {"bytes": len(content), "sha256": sha(content)}
            if row["files"] != manifest["payloads"]:
                raise SystemExit("Independent extraction contents differ: " + name)
            row["exact_payloads_match"] = True
            report["cases"].append(row)
    report["passed"] = len(report["cases"])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"passed": report["passed"], "payloads_per_image": len(manifest["payloads"]), "oracle_binary_sha256": report["oracle"]["binary_sha256"]}))


if __name__ == "__main__":
    main()
