#!/usr/bin/env python3
"""Verify the complete ink acceptance bundle and its semantic artifact seal."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def require(value, message):
    if not value:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / "bundle-files.json").read_bytes())
    commit = "bb7d98fe25cc6e3e69fdad3a2483a6fe08e83dfc"
    require(manifest["sourceCommit"] == commit and
            manifest["sourceTree"] == "cd8a4dae3208c45f3465be9f71d7cd3c789d1db0", "Bundle source identity")
    actual = [{"path": path.relative_to(root).as_posix(), "size": path.stat().st_size,
               "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
              for path in sorted(root.rglob("*")) if path.is_file() and
              "__pycache__" not in path.relative_to(root).parts and path != root / "bundle-files.json"]
    require(actual == manifest["files"], "Bundle file inventory/bytes differ")
    hosted = json.loads((root / "hosted-ci.json").read_bytes())
    require(hosted["run"]["head_sha"] == commit and hosted["run"]["id"] == 43384351772 and
            hosted["run"]["status"] == "completed" and hosted["run"]["conclusion"] == "success",
            "Hosted run identity/result")
    jobs = hosted["jobs"]["jobs"]
    require(len(jobs) == 2 and {job["name"] for job in jobs} == {"test", "openxml-schema"} and
            all(job["run_id"] == 43384351772 and job["status"] == "completed" and
                job["conclusion"] == "success" for job in jobs), "Hosted jobs differ")
    command = [sys.executable, str(root / "seal_validation_evidence.py"), "--directory", str(root)]
    if args.repository:
        command += ["--repository", str(args.repository)]
    if args.self_test:
        command += ["--self-test"]
    subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
