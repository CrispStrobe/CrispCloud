#!/usr/bin/env python3
"""Record a local qualification command against the exact saved source tree.

Usage: python3 docs/evidence/storage-binary-20261114/run_gate.py \
  --name final-native --output build/storage-binary-validation -- flutter test ...

Documentation/evidence may be added afterward. Every tracked non-doc path is
checked against its HEAD blob before and after execution. This runner does not
change dependencies, manifests, environment permissions, or the command.
"""

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def git(*args):
    return subprocess.check_output(["git", *args])


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inventory():
    files = {}
    mismatches = []
    for entry in git("ls-tree", "-rz", "--full-tree", "HEAD").split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, kind, expected = metadata.decode().split()
        path = raw_path.decode()
        if path.startswith("docs/") or kind != "blob":
            continue
        item = Path(path)
        try:
            data = os.readlink(item).encode() if mode == "120000" else item.read_bytes()
        except FileNotFoundError:
            mismatches.append(path)
            files[path] = {"missing": True}
            continue
        actual_blob = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
        files[path] = {"bytes": len(data), "sha256": sha(data), "git_blob": actual_blob}
        if actual_blob != expected:
            mismatches.append(path)
    for raw_path in git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0"):
        if raw_path and not raw_path.startswith(b"docs/"):
            mismatches.append(raw_path.decode())
    return {"files": files, "mismatches": sorted(set(mismatches))}


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.name):
        parser.error("name must be a simple artifact stem")
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("a command is required after --")
    root = Path(git("rev-parse", "--show-toplevel").decode().strip())
    os.chdir(root)
    args.output.mkdir(parents=True, exist_ok=True)
    revision = git("rev-parse", "HEAD").decode().strip()
    before = inventory()
    if before["mismatches"]:
        raise SystemExit(f"Unsaved source changes: {before['mismatches']}")
    before_bytes = encoded(before)
    inventory_path = args.output / f"{args.name}-source.json.gz"
    inventory_path.write_bytes(gzip.compress(before_bytes, mtime=0))
    package_map = Path(".dart_tool/package_config.json")
    package_before = sha(package_map.read_bytes()) if package_map.exists() else None
    started_at = datetime.now(timezone.utc).isoformat()
    started = time.monotonic()
    log_path = args.output / f"{args.name}.log"
    print(f"Running {args.name} at {revision} ({len(before['files'])} source paths)", flush=True)
    with log_path.open("wb") as log:
        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False)
    after = inventory()
    package_after = sha(package_map.read_bytes()) if package_map.exists() else None
    source_equal = before == after and revision == git("rev-parse", "HEAD").decode().strip()
    receipt = {
        "gate": args.name,
        "source_revision": revision,
        "source_tree": git("rev-parse", "HEAD^{tree}").decode().strip(),
        "command": command,
        "started_at_utc": started_at,
        "finished_at_utc": datetime.now(timezone.utc).isoformat(),
        "elapsed_seconds": round(time.monotonic() - started, 3),
        "exit_code": process.returncode,
        "source_paths": len(before["files"]),
        "source_inventory_sha256": sha(before_bytes),
        "source_inventory_file": inventory_path.name,
        "source_inventory_compressed_sha256": sha(inventory_path.read_bytes()),
        "source_unchanged": source_equal,
        "source_mismatches_after": after["mismatches"],
        "package_map_sha256_before": package_before,
        "package_map_sha256_after": package_after,
        "package_map_unchanged": package_before == package_after,
        "log_file": log_path.name,
        "log_sha256": sha(log_path.read_bytes()),
        "runner_sha256": sha(Path(__file__).read_bytes()),
    }
    (args.output / f"{args.name}-receipt.json").write_bytes(encoded(receipt))
    print(json.dumps(receipt, indent=2), flush=True)
    return process.returncode if process.returncode else (0 if source_equal and package_before == package_after else 1)


if __name__ == "__main__":
    sys.exit(main())
