#!/usr/bin/env python3
"""Create a reproducible metadata-only scan fixture, outside any real data tree.

Files are sparse: the reported logical sizes are intentional, not allocated
disk usage. The destination must not already exist. Nothing is downloaded.
"""

import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    root = args.directory.resolve()
    root.mkdir(parents=True, exist_ok=False)
    sizes = [0, 64, 1024, 8192, 65536]
    extensions = ["txt", "jpg", "mp4", "bin", "pdf"]
    records = []
    for group in range(40):
        for leaf in range(10):
            folder = root / f"group_{group:02d}" / f"folder_{leaf:02d}"
            folder.mkdir(parents=True)
            for number in range(60):
                file = folder / f"file_{number:03d}.{extensions[number % 5]}"
                size = sizes[number % 5]
                with file.open("wb") as stream:
                    stream.truncate(size)
                records.append([file.relative_to(root).as_posix(), size])
    for number in range(20):
        (root / f"empty_{number:02d}").mkdir()
    records.sort()
    digest = hashlib.sha256(
        json.dumps(records, separators=(",", ":")).encode()
    ).hexdigest()
    manifest = {
        "files": len(records),
        "folders": 460,
        "logicalBytes": sum(row[1] for row in records),
        "filesDigest": digest,
        "description": "ASCII names, no symlinks, 20 empty folders; sparse files",
    }
    destination = root.with_name(root.name + ".manifest.json")
    destination.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Created {root}; verification manifest: {destination}")


if __name__ == "__main__":
    main()
