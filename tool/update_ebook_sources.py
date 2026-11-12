#!/usr/bin/env python3
"""Explicitly record a reviewed ebook Git tree; never edits dependency pins."""

import argparse
import hashlib
import json
from pathlib import Path

from verify_ebook_sources import MANIFEST, PACKAGES, REPOSITORY, ROOT, git, tree_entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    revision = git(args.checkout, "rev-parse", args.revision + "^{commit}").decode().strip()
    files = tree_entries(args.checkout, revision)
    for name, record in files.items():
        data = git(args.checkout, "cat-file", "blob", record["git_blob"])
        record.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    manifest = {
        "schema_version": 1,
        "repository": REPOSITORY,
        "revision": revision,
        "git_tree": git(args.checkout, "rev-parse", revision + "^{tree}").decode().strip(),
        "packages": PACKAGES,
        "files": files,
    }
    (ROOT / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Recorded {len(files)} source files from {revision}; review before committing.")


if __name__ == "__main__":
    main()
