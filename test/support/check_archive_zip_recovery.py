#!/usr/bin/env python3
"""Check actual Dart recovery candidates with Python's independent ZIP reader.

Generate the input receipt by running archive_zip_recovery_web_acceptance.dart
with --emit-candidates. Python verifies each expected filename, length, CRC and
SHA256 using the independently generated reference manifest. No result hash or
filename asserted by the Dart receipt is taken as an expected value.
"""

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 CrispCloud contributors

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidates", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    manifest = json.loads((root / "test/fixtures/archives/zip-recovery-reference-manifest.json").read_text())
    receipt = json.loads(args.candidates.read_text())
    candidates = receipt["candidates"]
    expected_cases = {name: row for name, row in manifest["cases"].items() if row["expected_recoverable_names"]}
    if set(candidates) != set(expected_cases):
        raise SystemExit("Candidate inventory differs from independently expected cases")
    report = {"schema": 1, "oracle": "Python standard library zipfile, testzip CRC and SHA256", "candidate_receipt_sha256": hashlib.sha256(args.candidates.read_bytes()).hexdigest(), "cases": []}
    for name, encoded in candidates.items():
        data = base64.b64decode(encoded, validate=True)
        expected = expected_cases[name]["expected_recoverable_names"]
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            if sorted(archive.namelist()) != sorted(expected):
                raise SystemExit("Unexpected recovered namespace: " + name)
            if archive.testzip() is not None:
                raise SystemExit("Recovered member CRC failed: " + name)
            files = {}
            for member in archive.infolist():
                if member.is_dir() or member.flag_bits & 1:
                    raise SystemExit("Unexpected directory/encryption in reference candidate")
                payload = archive.read(member)
                actual = {"bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
                if actual != manifest["payloads"][member.filename]:
                    raise SystemExit("Recovered payload mismatch: " + name + "/" + member.filename)
                files[member.filename] = actual
        report["cases"].append({"name": name, "archive_bytes": len(data), "archive_sha256": hashlib.sha256(data).hexdigest(), "files": files, "all_crcs_match": True})
    report["passed"] = len(report["cases"])
    report["verified_members"] = sum(len(row["files"]) for row in report["cases"])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"passed": report["passed"], "verified_members": report["verified_members"]}))


if __name__ == "__main__":
    main()
