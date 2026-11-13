#!/usr/bin/env python3
"""Verify the pinned File Viewer subset, not all CrispCloud dependency licenses.

The reviewed identities below deliberately live outside UPSTREAM.json. Changing
both a snapshot and its manifest hash must still require a review of this guard.
Only stdlib Python is needed; no network or upstream checkout is consulted.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
import sys
from pathlib import Path, PurePosixPath
from typing import Any, NamedTuple


SNAPSHOT_DIR = "packages/file_viewer_binary"
DERIVATIVE_PATH = "lib/services/binary_structure_service.dart"
APPROVED_METADATA = {
    "schema_version": 1,
    "repository": "https://github.com/flyfish-dev/file-viewer",
    "commit": "d264009ca6efb3daed79a39d1ae63133e0f25558",
    "upstream_package": "@file-viewer/renderer-binary",
    "upstream_version": "3.3.3",
    "license": "Apache-2.0",
    "copyright": "Copyright 2026 Flyfish Viewer",
    "upstream_notice_file": None,
    "runtime_dependencies_added": [],
}
APPROVED_FILES = {
    "LICENSE": {
        "upstream_path": "packages/renderers/binary/LICENSE",
        "local_path": "LICENSE",
        "git_blob_sha1": "59121b29efbabb216432f367c8071d1f6019c43f",
        "sha256": "55ce5d9fb8138a058b60c431cb9e68e13dd3f90691f73a757e38f06fed81e69b",
        "bytes": 9140,
        "modified": False,
        "license": "Apache-2.0",
    },
    "upstream/parser.ts": {
        "upstream_path": "packages/renderers/binary/src/parser.ts",
        "local_path": "upstream/parser.ts",
        "git_blob_sha1": "988d602b44888d4e5643a03ec9ecfe3c7623800a",
        "sha256": "d3580e4d9ef2ce25d67e0fb37eccdaf8a3b5987bf8ae29de19aab090a7a1ae8c",
        "bytes": 11840,
        "modified": False,
        "license": "Apache-2.0",
    },
    "upstream/types.ts": {
        "upstream_path": "packages/renderers/binary/src/types.ts",
        "local_path": "upstream/types.ts",
        "git_blob_sha1": "f5da7234b6ae1623e7db7c3e00a1daafc99d800f",
        "sha256": "e01abcc75a4d756a2bf3ccf4d70b169c00be8509b798fd53147b754c8ee3b83c",
        "bytes": 2199,
        "modified": False,
        "license": "Apache-2.0",
    },
}
APPROVED_IMPORTS = ["dart:typed_data"]
ALLOWED_FILES = set(APPROVED_FILES) | {"UPSTREAM.md", "UPSTREAM.json"}
ALLOWED_DIRECTORIES = {"upstream"}


class VerificationError(ValueError):
    """A source/provenance boundary differs from the reviewed allowlist."""


def _relative_path(value: Any, label: str) -> str:
    if (
        not isinstance(value, str)
        or not value
        or "\\" in value
        or ":" in value
        or "\0" in value
        or PurePosixPath(value).is_absolute()
        or any(part in {"", ".", ".."} for part in value.split("/"))
    ):
        raise VerificationError(f"Unsafe {label}: {value!r}")
    return value


def _path_without_symlinks(root: Path, relative: str) -> Path:
    _relative_path(relative, "repository path")
    current = root
    if current.is_symlink():
        raise VerificationError(f"Symlink is not allowed: {current}")
    for part in relative.split("/"):
        current = current / part
        if current.is_symlink():
            raise VerificationError(f"Symlink is not allowed: {current}")
    return current


def _read_file(path: Path) -> bytes:
    try:
        mode = path.lstat().st_mode
        if not stat.S_ISREG(mode):
            raise VerificationError(f"Expected a regular file: {path}")
        return path.read_bytes()
    except OSError as error:
        raise VerificationError(f"Cannot read {path}: {error}") from error


def _json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise VerificationError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def _exact(actual: Any, expected: Any, label: str) -> None:
    # bool is a subclass of int in Python: reject e.g. schema_version=true.
    if type(actual) is not type(expected) or actual != expected:
        raise VerificationError(f"Unapproved {label}: {actual!r}")


def _check_tree(directory: Path) -> None:
    if not directory.is_dir():
        raise VerificationError(f"Missing snapshot directory: {directory}")
    found: set[str] = set()

    def visit(parent: Path) -> None:
        for child in parent.iterdir():
            relative = child.relative_to(directory).as_posix()
            if child.is_symlink():
                raise VerificationError(f"Symlink is not allowed: {child}")
            if child.is_dir():
                if relative not in ALLOWED_DIRECTORIES:
                    raise VerificationError(f"Unexpected snapshot directory: {relative}")
                visit(child)
            else:
                if relative not in ALLOWED_FILES:
                    raise VerificationError(f"Unexpected snapshot file: {relative}")
                if not stat.S_ISREG(child.lstat().st_mode):
                    raise VerificationError(f"Expected a regular file: {child}")
                found.add(relative)

    visit(directory)
    missing = ALLOWED_FILES - found
    if missing:
        raise VerificationError(f"Missing snapshot files: {', '.join(sorted(missing))}")


class _Token(NamedTuple):
    kind: str
    value: str
    start: int


def _dart_tokens(source: str) -> list[_Token]:
    """Read comments/quoted strings separately so hidden import URIs are checked.

    This conservative directive guard is not a Dart type/syntax checker; the
    normal Dart analyzer remains responsible for validating the complete file.
    """
    tokens: list[_Token] = []
    index = 0
    while index < len(source):
        if source[index].isspace():
            index += 1
            continue
        if source.startswith("//", index):
            end = source.find("\n", index)
            index = len(source) if end < 0 else end + 1
            continue
        if source.startswith("/*", index):
            depth = 1
            index += 2
            while index < len(source) and depth:
                if source.startswith("/*", index):
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            if depth:
                raise VerificationError("Unclosed Dart block comment")
            continue
        start = index
        raw = source[index] == "r" and index + 1 < len(source) and source[index + 1] in "\"'"
        if raw:
            index += 1
        if source[index] in "\"'":
            quote = source[index]
            delimiter = quote * 3 if source.startswith(quote * 3, index) else quote
            index += len(delimiter)
            content_start = index
            while index < len(source):
                if source.startswith(delimiter, index):
                    tokens.append(_Token("string", source[content_start:index], start))
                    index += len(delimiter)
                    break
                if not raw and source[index] == "\\":
                    index += 2
                else:
                    index += 1
            else:
                raise VerificationError("Unclosed Dart quoted string")
            continue
        if source[index].isalpha() or source[index] in "_$":
            index += 1
            while index < len(source) and (source[index].isalnum() or source[index] in "_$"):
                index += 1
            tokens.append(_Token("identifier", source[start:index], start))
        else:
            tokens.append(_Token("symbol", source[index], start))
            index += 1
    return tokens


def _check_derivative(path: Path) -> None:
    try:
        source = _read_file(path).decode("utf-8")
    except UnicodeDecodeError as error:
        raise VerificationError("Dart derivative is not UTF-8") from error
    tokens = _dart_tokens(source)
    header = source[:tokens[0].start] if tokens else source
    for pattern, name in (
        (r"\bCopyright 2026 Flyfish Viewer\b", "upstream copyright"),
        (r"SPDX-License-Identifier:\s*Apache-2\.0(?:\s*\*/)?\s*$", "Apache SPDX notice"),
        (r"\bModified\s+Dart\s+port\b", "Dart modification notice"),
        (r"packages/file_viewer_binary/UPSTREAM\.md", "provenance reference"),
    ):
        if not re.search(pattern, header, re.MULTILINE):
            raise VerificationError(f"Missing leading {name} in {DERIVATIVE_PATH}")

    imports: list[str] = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token.kind != "identifier" or token.value not in {"import", "export", "part"}:
            index += 1
            continue
        if token.value != "import":
            raise VerificationError(f"Unapproved Dart {token.value} directive")
        end = index + 1
        while end < len(tokens) and tokens[end].value != ";":
            end += 1
        if end == len(tokens):
            raise VerificationError("Unterminated Dart import directive")
        directive = tokens[index + 1:end]
        # The reviewed parser needs exactly one plain SDK import. Requiring this
        # simple form also rejects conditional imports and escaped URI tricks.
        if len(directive) != 1 or directive[0].kind != "string":
            raise VerificationError("Unapproved conditional or complex Dart import")
        uri = directive[0].value
        if not uri.startswith("dart:") or uri not in APPROVED_IMPORTS:
            raise VerificationError(f"Unapproved Dart import URI: {uri!r}")
        imports.append(uri)
        index = end + 1
    _exact(imports, APPROVED_IMPORTS, "Dart import list")


def verify(repository_root: Path) -> None:
    """Raise VerificationError when this reviewed source boundary has drifted."""
    root = Path(repository_root).absolute()
    snapshot = _path_without_symlinks(root, SNAPSHOT_DIR)
    _check_tree(snapshot)
    manifest_path = _path_without_symlinks(root, f"{SNAPSHOT_DIR}/UPSTREAM.json")
    try:
        manifest = json.loads(_read_file(manifest_path), object_pairs_hook=_json_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise VerificationError(f"Invalid UPSTREAM.json: {error}") from error
    if not isinstance(manifest, dict):
        raise VerificationError("UPSTREAM.json must contain an object")
    for key, expected in APPROVED_METADATA.items():
        if key not in manifest:
            raise VerificationError(f"Missing manifest field: {key}")
        _exact(manifest[key], expected, f"manifest {key}")

    entries = manifest.get("upstream_file_allowlist")
    if not isinstance(entries, list) or len(entries) != len(APPROVED_FILES):
        raise VerificationError("The upstream allowlist must contain exactly three reviewed files")
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise VerificationError("Each upstream allowlist entry must be an object")
        local = _relative_path(entry.get("local_path"), "local_path")
        _relative_path(entry.get("upstream_path"), "upstream_path")
        if local not in APPROVED_FILES or local in seen:
            raise VerificationError(f"Unapproved or duplicate upstream file: {local}")
        seen.add(local)
        expected = APPROVED_FILES[local]
        if set(entry) != set(expected):
            raise VerificationError(f"Unexpected manifest fields for {local}")
        for key, value in expected.items():
            _exact(entry[key], value, f"{local} {key}")
        data = _read_file(_path_without_symlinks(root, f"{SNAPSHOT_DIR}/{local}"))
        actual_blob = hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()
        _exact(len(data), expected["bytes"], f"{local} byte length")
        _exact(hashlib.sha256(data).hexdigest(), expected["sha256"], f"{local} SHA-256")
        _exact(actual_blob, expected["git_blob_sha1"], f"{local} Git blob SHA-1")

    derivative = manifest.get("derivative")
    if not isinstance(derivative, dict):
        raise VerificationError("Missing Dart derivative manifest")
    _relative_path(derivative.get("path"), "derivative path")
    for key, expected in {
        "path": DERIVATIVE_PATH,
        "language": "Dart",
        "imports": APPROVED_IMPORTS,
        "maximum_prefix_bytes": 65536,
    }.items():
        _exact(derivative.get(key), expected, f"derivative {key}")
    changes = derivative.get("changes")
    if not isinstance(changes, list) or not changes or not all(isinstance(item, str) and item.strip() for item in changes):
        raise VerificationError("Missing derivative modification record")
    _check_derivative(_path_without_symlinks(root, DERIVATIVE_PATH))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args(argv)
    try:
        verify(args.repo_root)
    except (VerificationError, OSError) as error:
        print(f"File Viewer subset verification failed: {error}", file=sys.stderr)
        return 1
    print("Verified the 3 pinned Apache File Viewer files and Dart attribution/import boundary.")
    print("Scope: this selected subset only; not a scan of all CrispCloud dependencies.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
