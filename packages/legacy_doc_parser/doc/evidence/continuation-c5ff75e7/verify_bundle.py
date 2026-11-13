#!/usr/bin/env python3
"""Verify the complete final portable/schema bundle, including hosted receipts."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import verify_hosted_ci


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / "bundle-files.json").read_bytes())
    verify_hosted_ci.require(manifest["sourceCommit"] == verify_hosted_ci.COMMIT and
                            manifest["sourceTree"] == "25bd05c12fa2272a32ec2aaba2cc0117be5bed96", "Bundle source identity")
    actual = [{"path": p.relative_to(root).as_posix(), "size": p.stat().st_size,
               "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
              for p in sorted(root.rglob("*")) if p.is_file() and
              "__pycache__" not in p.relative_to(root).parts and p != root / "bundle-files.json"]
    verify_hosted_ci.require(actual == manifest["files"], "Bundle file inventory/bytes differ")
    command = [sys.executable, str(root / "seal_validation_evidence.py"), "--directory", str(root)]
    if args.repository:
        command += ["--repository", str(args.repository)]
    if args.self_test:
        command += ["--self-test"]
    subprocess.run(command, check=True)
    print(json.dumps(verify_hosted_ci.verify(root, args.self_test), sort_keys=True))


if __name__ == "__main__":
    main()
