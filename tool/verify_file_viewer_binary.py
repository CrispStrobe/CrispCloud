#!/usr/bin/env python3
"""Verify the pinned File Viewer binary subset, not all application licenses.

Source identities remain separate from UPSTREAM.json so rehashing a changed
snapshot in its manifest still requires an explicit review of this allowlist.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from file_viewer_provenance import VerificationError, verify_subset


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



def verify(repository_root: Path) -> None:
    verify_subset(
        repository_root,
        snapshot_dir=SNAPSHOT_DIR,
        derivative_path=DERIVATIVE_PATH,
        approved_metadata=APPROVED_METADATA,
        approved_files=APPROVED_FILES,
        approved_imports=APPROVED_IMPORTS,
        derivative_metadata={"maximum_prefix_bytes": 65536},
    )


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
