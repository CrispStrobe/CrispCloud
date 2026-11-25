#!/usr/bin/env python3
"""Keep the reviewed macos/Podfile.lock across a CI `pod install`.

CocoaPods records a local pod's SPEC CHECKSUM as the SHA-1 of the podspec JSON
it writes under Pods/Local Podspecs. Ruby's json gem changed how
pretty_generate prints an empty array or object (multi-line in older
versions, `[]` in newer ones). Every Flutter plugin declares an unversioned
FlutterMacOS dependency, so the same plugins get different checksums on a
runner with an older json gem than on a developer Mac.

This guard accepts exactly that difference: a changed checksum is tolerated
only when the runner's podspec JSON, with empty arrays and objects
normalized to `[]`/`{}`, hashes to the committed value. The trailing
COCOAPODS: tool-version line may differ too. Then the committed lock is
restored. Anything else fails, with the offending lines.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

EMPTY_ARRAY = re.compile(r"\[\s*\n\s*\]")
EMPTY_OBJECT = re.compile(r"\{\s*\n\s*\}")
CHECKSUM_LINE = re.compile(r"^  (?P<name>[^ :]+): (?P<sha>[0-9a-f]{40})$")


def normalized_sha1(podspec_json: bytes) -> str:
    text = podspec_json.decode("utf-8")
    text = EMPTY_OBJECT.sub("{}", EMPTY_ARRAY.sub("[]", text))
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


def section(lines: list[str], title: str) -> list[str]:
    out, inside = [], False
    for line in lines:
        if line == f"{title}:":
            inside = True
            continue
        if inside and line and not line.startswith(" "):
            break
        if inside:
            out.append(line)
    return out


def checksums(lines: list[str]) -> dict[str, str]:
    found = {}
    for line in section(lines, "SPEC CHECKSUMS"):
        match = CHECKSUM_LINE.match(line)
        if match:
            found[match["name"]] = match["sha"]
    return found


def local_pods(lines: list[str]) -> set[str]:
    return {line.strip().rstrip(":") for line in section(lines, "EXTERNAL SOURCES")
            if line.startswith("  ") and not line.startswith("    ")}


def problems(committed: str, built: str, podspecs: Path) -> list[str]:
    old, new = committed.splitlines(), built.splitlines()
    strip = lambda lines: [line for line in lines if not line.startswith("COCOAPODS: ")]
    old_sums, new_sums = checksums(old), checksums(new)
    without_sums = lambda lines: [line for line in strip(lines)
                                  if line not in section(lines, "SPEC CHECKSUMS")]
    issues = []
    if without_sums(old) != without_sums(new) or old_sums.keys() != new_sums.keys():
        issues.append("pod versions, dependencies or sources changed")
    locals_ = local_pods(old)
    for name in sorted(old_sums.keys() & new_sums.keys()):
        if old_sums[name] == new_sums[name]:
            continue
        if name not in locals_:
            issues.append(f"{name}: checksum of a downloaded pod changed")
            continue
        spec = podspecs / f"{name}.podspec.json"
        if not spec.is_file():
            issues.append(f"{name}: no {spec} to verify the changed checksum")
        elif normalized_sha1(spec.read_bytes()) != old_sums[name]:
            issues.append(f"{name}: podspec content differs, not only JSON formatting")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--check-only", action="store_true",
                        help="report without restoring the committed lock")
    args = parser.parse_args()
    lock = "macos/Podfile.lock"
    built = (args.root / lock).read_text()
    committed = subprocess.check_output(
        ["git", "-C", str(args.root), "show", f"HEAD:{lock}"], text=True)
    if built == committed:
        print(f"{lock} unchanged by pod install")
        return 0
    issues = problems(committed, built, args.root / "macos/Pods/Local Podspecs")
    if issues:
        subprocess.run(["git", "-C", str(args.root), "--no-pager", "diff", "--", lock])
        for issue in issues:
            print(f"::error::{lock}: {issue}")
        print("Commit the updated lock after review if the change is intended.")
        return 1
    if not args.check_only:
        (args.root / lock).write_text(committed)
    print(f"{lock}: only json-gem formatting of local podspec checksums differed; "
          "committed lock kept")
    return 0


if __name__ == "__main__":
    sys.exit(main())
