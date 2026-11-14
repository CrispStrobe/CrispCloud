#!/usr/bin/env python3
"""Verify the pinned BSD LZFSE subset and the Dart port's import boundary.

The fixed source identities below are separate from the editable manifest.
This checks only the selected LZFSE source, not all CrispCloud dependencies.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import stat
import sys
from pathlib import Path

from file_viewer_provenance import VerificationError, _dart_tokens


APPROVED = {'repository': 'https://github.com/lzfse/lzfse',
 'commit': 'e634ca58b4821d9f3d560cdc6df5dec02ffc93fd',
 'license': 'BSD-3-Clause',
 'files': [{'upstream_path': 'LICENSE',
            'local_path': 'LICENSE',
            'git_blob_sha1': 'c81aa178b42d5533bac516af7fc4d1d505da48d3',
            'sha256': '2a20082c2219edbbdb2e862a0566ba4f762a564ade7c04b09250ae4464bc4b32',
            'bytes': 1514,
            'modified': False,
            'license': 'BSD-3-Clause'},
           {'upstream_path': 'src/lzfse_decode_base.c',
            'local_path': 'upstream/lzfse_decode_base.c',
            'git_blob_sha1': '31fe859104bef23aec01d95ce2aa7fab66e4a840',
            'sha256': '721b4061e4e655f0940b7cabcf506356c152716526e630981caf0e708d2f73d9',
            'bytes': 24921,
            'modified': False,
            'license': 'BSD-3-Clause'},
           {'upstream_path': 'src/lzfse_fse.c',
            'local_path': 'upstream/lzfse_fse.c',
            'git_blob_sha1': '631ada062324d18abc7c21991fd10babf90dfa65',
            'sha256': 'a97e309975487af269456a4e87ef516aedaf82ce469e37971fd5676f9cd5956b',
            'bytes': 7945,
            'modified': False,
            'license': 'BSD-3-Clause'},
           {'upstream_path': 'src/lzfse_fse.h',
            'local_path': 'upstream/lzfse_fse.h',
            'git_blob_sha1': '88460129804f0db2059456e0e8917ce09361b77f',
            'sha256': '4e5c2228a4bb5e5f3faf4639d5688bc7caa5cf0c0f3a971ada4fbe3631f3a533',
            'bytes': 24556,
            'modified': False,
            'license': 'BSD-3-Clause'},
           {'upstream_path': 'src/lzfse_internal.h',
            'local_path': 'upstream/lzfse_internal.h',
            'git_blob_sha1': '7ea5a30a0fe480423c1cad9f2ff5bcb1cd33e7f8',
            'sha256': 'd08dc29d5440775de279d36783729131329df10cffd43ec6eff7dcfceef9f570',
            'bytes': 25264,
            'modified': False,
            'license': 'BSD-3-Clause'},
           {'upstream_path': 'src/lzvn_decode_base.c',
            'local_path': 'upstream/lzvn_decode_base.c',
            'git_blob_sha1': 'c30180ecd1fec7178bcd0be9186666b4cc140fb3',
            'sha256': '434647c83d4f3ed95c11465c5a3ec46f992ec94843928138039ea40be623957d',
            'bytes': 22090,
            'modified': False,
            'license': 'BSD-3-Clause'},
           {'upstream_path': 'src/lzfse_encode_base.c',
            'local_path': 'upstream/lzfse_encode_base.c',
            'git_blob_sha1': '367d7a23bb0817e48eca0801e7cb9886202652b8',
            'sha256': 'ad69af28e09d5a4e40912bfbe67fb4c570a1e3186c7621dca15b72c41830e34e',
            'bytes': 27437,
            'modified': False,
            'license': 'BSD-3-Clause'}]}
APPROVED_IMPORTS = ["dart:typed_data", "archive_types.dart"]


def verify(root: Path) -> None:
    directory = root / "packages/apple_lzfse"
    allowed = {row["local_path"] for row in APPROVED["files"]} | {
        "UPSTREAM.md", "UPSTREAM.json"
    }
    if directory.is_symlink() or not directory.is_dir():
        raise VerificationError("Missing or linked LZFSE snapshot directory")
    found = set()
    for path in directory.rglob("*"):
        relative = path.relative_to(directory).as_posix()
        if path.is_symlink():
            raise VerificationError(f"Unexpected symlink: {relative}")
        if path.is_dir():
            if relative != "upstream":
                raise VerificationError(f"Unexpected source directory: {relative}")
            continue
        if not stat.S_ISREG(path.stat().st_mode) or relative not in allowed:
            raise VerificationError(f"Unexpected source file: {relative}")
        found.add(relative)
    if found != allowed:
        raise VerificationError(f"Missing source files: {sorted(allowed - found)}")

    manifest = json.loads((directory / "UPSTREAM.json").read_text())
    for key in ("repository", "commit", "license"):
        if manifest.get(key) != APPROVED[key]:
            raise VerificationError(f"Unreviewed {key}")
    if manifest.get("runtime_dependencies_added") != []:
        raise VerificationError("Unreviewed runtime dependency")
    if manifest.get("upstream_file_allowlist") != APPROVED["files"]:
        raise VerificationError("Manifest differs from approved source identities")
    for row in APPROVED["files"]:
        data = (directory / row["local_path"]).read_bytes()
        blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if (len(data) != row["bytes"] or blob != row["git_blob_sha1"] or
                hashlib.sha256(data).hexdigest() != row["sha256"]):
            raise VerificationError(f"Changed source: {row['local_path']}")

    derivative = root / "lib/services/archive_lzfse_codec.dart"
    if derivative.is_symlink():
        raise VerificationError("Linked Dart derivative")
    source = derivative.read_text()
    license_text = (directory / "LICENSE").read_text()
    if " ".join(license_text.split()) not in " ".join(source.split()):
        raise VerificationError("Full upstream BSD notice missing from derivative")
    for notice in ("Modified", APPROVED["commit"], "packages/apple_lzfse/"):
        if notice not in source:
            raise VerificationError(f"Missing Dart attribution: {notice}")
    tokens = _dart_tokens(source)
    imports = []
    braces = 0
    for index, token in enumerate(tokens):
        if token.kind == "symbol" and token.value == "{":
            braces += 1
        elif token.kind == "symbol" and token.value == "}":
            braces -= 1
        if braces != 0:
            continue
        if token.kind != "identifier" or token.value not in {"import", "export", "part"}:
            continue
        if token.value != "import" or index + 2 >= len(tokens):
            raise VerificationError("Unreviewed Dart directive")
        uri, end = tokens[index + 1:index + 3]
        if uri.kind != "string" or end.value != ";":
            raise VerificationError("Unreviewed complex Dart import")
        imports.append(uri.value)
    if imports != APPROVED_IMPORTS:
        raise VerificationError(f"Unreviewed Dart imports: {imports}")
    if manifest.get("derivative", {}).get("imports") != APPROVED_IMPORTS:
        raise VerificationError("Manifest import boundary differs")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        verify(args.repo_root)
    except (VerificationError, OSError, ValueError) as error:
        print(f"LZFSE source verification failed: {error}", file=sys.stderr)
        return 1
    print("Verified seven pinned BSD-3-Clause LZFSE files, Dart attribution and imports.")
    print("Scope: selected LZFSE source only; no native library or new Pub dependency.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
