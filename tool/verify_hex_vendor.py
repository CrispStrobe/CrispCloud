#!/usr/bin/env python3
"""Verify the vendored hex package against the pinned fork's Git blob IDs.

Read-only and offline. CRLF checkout conversion is normalized for text files.
The fork revision and blob IDs must be refreshed together after reviewing a sync.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath


def verify(root: Path) -> list[str]:
    package = root / "packages" / "madedit2_hex"
    manifest = json.loads((package / "FORK.json").read_text(encoding="utf-8"))
    if manifest.get("repository") != "https://github.com/CrispStrobe/madedit2":
        raise ValueError("Unexpected fork repository")
    if manifest.get("path") != "packages/madedit2_hex":
        raise ValueError("Unexpected fork package path")
    if not re.fullmatch(r"[0-9a-f]{40}", manifest.get("revision", "")):
        raise ValueError("The fork revision must be an immutable 40-digit commit")
    expected = manifest.get("files")
    if not isinstance(expected, dict) or not expected:
        raise ValueError("Missing fork file fingerprints")
    actual = {"LICENSE", "pubspec.yaml", "analysis_options.yaml"}
    for directory in ("lib", "test"):
        actual.update(p.relative_to(package).as_posix()
                      for p in (package / directory).rglob("*.dart"))
    errors = []
    if actual != set(expected):
        errors.append("Tracked file set differs: " +
                      ", ".join(sorted(actual.symmetric_difference(expected))))
    for name, digest in sorted(expected.items()):
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or "\\" in name:
            raise ValueError("Unsafe manifest path")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{40}", digest):
            raise ValueError("Invalid blob fingerprint: " + name)
        path = package.joinpath(*relative.parts)
        if path.is_symlink() or not path.is_file():
            errors.append("Missing or symlinked file: " + name)
            continue
        if not path.resolve().is_relative_to(package.resolve()):
            raise ValueError("Manifest path escapes package")
        data = path.read_bytes().replace(b"\r\n", b"\n")
        blob = b"blob " + str(len(data)).encode("ascii") + b"\0" + data
        if hashlib.sha1(blob).hexdigest() != digest:
            errors.append("Changed since pinned fork: " + name)
    return errors


def main() -> int:
    try:
        errors = verify(Path(__file__).resolve().parents[1])
        if errors:
            print("\n".join(errors), file=sys.stderr)
            return 1
    except (OSError, ValueError, TypeError) as error:
        print("Hex vendor verification failed: " + str(error), file=sys.stderr)
        return 1
    print("Hex package matches its pinned fork fingerprints.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
