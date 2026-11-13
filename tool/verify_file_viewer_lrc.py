#!/usr/bin/env python3
"""Verify the pinned File Viewer LRC subset, not all application licenses.

The source allowlist stays independent of UPSTREAM.json so rehashing altered
snapshots cannot approve them. This guard checks provenance, attribution,
absence of Dart import/export/part directives, and the reviewed limits recorded
in metadata. Parser behavior and enforcement of its limits have separate tests.
Only stdlib Python is needed; no network or upstream checkout is consulted.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from file_viewer_provenance import VerificationError, verify_subset


SNAPSHOT_DIR = "packages/file_viewer_lrc"
DERIVATIVE_PATH = "lib/services/lrc_parser.dart"
APPROVED_METADATA = {
    "schema_version": 1,
    "repository": "https://github.com/flyfish-dev/file-viewer",
    "commit": "d264009ca6efb3daed79a39d1ae63133e0f25558",
    "upstream_package": "@file-viewer/renderer-text",
    "upstream_version": "3.3.3",
    "license": "Apache-2.0",
    "copyright": "Copyright 2026 Flyfish Viewer",
    "upstream_notice_file": None,
    "runtime_dependencies_added": [],
}
APPROVED_FILES = {
    "LICENSE": {
        "upstream_path": "packages/renderers/text/LICENSE",
        "local_path": "LICENSE",
        "git_blob_sha1": "59121b29efbabb216432f367c8071d1f6019c43f",
        "sha256": "55ce5d9fb8138a058b60c431cb9e68e13dd3f90691f73a757e38f06fed81e69b",
        "bytes": 9140,
        "modified": False,
        "license": "Apache-2.0",
    },
    "upstream/lrcParser.ts": {
        "upstream_path": "packages/renderers/text/src/lrcParser.ts",
        "local_path": "upstream/lrcParser.ts",
        "git_blob_sha1": "c701adce35bc0c2d8be239aa077543aaf6fbad60",
        "sha256": "b0f42a4f200dd32a37f11cc3bae1ea49b47feffb8fac7bf274ddaf0ec935b59b",
        "bytes": 4281,
        "modified": False,
        "license": "Apache-2.0",
    },
}
APPROVED_IMPORTS: list[str] = []
APPROVED_LIMITS = {
    "lrcMaxSourceCodeUnits": 2_000_000,
    "lrcMaxCues": 10_000,
    "lrcMaxExpandedWords": 50_000,
    "lrcMaxMetadata": 1_000,
    "lrcMaxTimelineMilliseconds": 20_000_000_000_000,
}


def verify(repository_root: Path) -> None:
    verify_subset(
        repository_root,
        snapshot_dir=SNAPSHOT_DIR,
        derivative_path=DERIVATIVE_PATH,
        approved_metadata=APPROVED_METADATA,
        approved_files=APPROVED_FILES,
        approved_imports=APPROVED_IMPORTS,
        derivative_metadata={
            "limits": APPROVED_LIMITS,
            "maximum_timeline_milliseconds": APPROVED_LIMITS[
                "lrcMaxTimelineMilliseconds"
            ],
        },
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args(argv)
    try:
        verify(args.repo_root)
    except (VerificationError, OSError) as error:
        print(f"File Viewer LRC verification failed: {error}", file=sys.stderr)
        return 1
    print(
        "Verified the 2 pinned Apache File Viewer LRC files, Dart attribution, "
        "no-import boundary and limit metadata."
    )
    print("Scope: this selected subset only; not a scan of all CrispCloud dependencies.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
