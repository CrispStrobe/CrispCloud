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
    parser.add_argument(
        "--shape", choices=("balanced", "wide", "empty"), default="balanced",
        help="balanced: 24,000 files/460 folders; wide: 24,000 root files; empty: 1,010 folders",
    )
    args = parser.parse_args()
    root = args.directory.resolve()
    root.mkdir(parents=True, exist_ok=False)
    sizes = [0, 64, 1024, 8192, 65536]
    extensions = ["txt", "jpg", "mp4", "bin", "pdf"]
    records = []

    def add_file(folder, number, width):
        file = folder / f"file_{number:0{width}d}.{extensions[number % 5]}"
        size = sizes[number % 5]
        with file.open("wb") as stream:
            stream.truncate(size)
        records.append([file.relative_to(root).as_posix(), size])

    if args.shape == "balanced":
        for group in range(40):
            for leaf in range(10):
                folder = root / f"group_{group:02d}" / f"folder_{leaf:02d}"
                folder.mkdir(parents=True)
                for number in range(60):
                    add_file(folder, number, 3)
        for number in range(20):
            (root / f"empty_{number:02d}").mkdir()
        folders = 460
        description = "ASCII names, no symlinks, 20 empty folders; sparse files"
    elif args.shape == "wide":
        for number in range(24000):
            add_file(root, number, 5)
        folders = 0
        description = "24,000 direct file children, ASCII names, no symlinks; sparse files"
    else:
        for group in range(10):
            for leaf in range(100):
                (root / f"group_{group:02d}" / f"empty_{leaf:03d}").mkdir(parents=True)
        folders = 1010
        description = "10 parent folders and 1,000 empty child folders; no files or symlinks"
    records.sort()
    digest = hashlib.sha256(
        json.dumps(records, separators=(",", ":")).encode()
    ).hexdigest()
    manifest = {
        "files": len(records),
        "folders": folders,
        "logicalBytes": sum(row[1] for row in records),
        "filesDigest": digest,
        "description": description,
        "shape": args.shape,
    }
    destination = root.with_name(root.name + ".manifest.json")
    destination.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Created {root}; verification manifest: {destination}")


if __name__ == "__main__":
    main()
