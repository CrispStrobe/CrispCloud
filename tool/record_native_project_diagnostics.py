#!/usr/bin/env python3
"""Retain a failed Apple build's exact project delta, never release approval."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("ios", "macos"))
    args = parser.parse_args()
    relative = f"{args.platform}/Runner.xcodeproj/project.pbxproj"
    output = ROOT / "build" / "source-diagnostics" / args.platform
    output.mkdir(parents=True, exist_ok=True)
    try:
        project = ROOT
        for part in Path(relative).parts:
            project /= part
            if project.is_symlink():
                raise ValueError("Refusing to read a symlinked project path")
        if not project.is_file():
            raise ValueError("Expected project is not a regular file")

        def git(*arguments: str) -> bytes:
            return subprocess.run(
                ["git", *arguments], cwd=ROOT, check=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            ).stdout

        (output / "source-commit.txt").write_bytes(git("rev-parse", "HEAD"))
        (output / "project.head.pbxproj").write_bytes(git("show", f"HEAD:{relative}"))
        (output / "project.built.pbxproj").write_bytes(project.read_bytes())
        patch = git("diff", "--no-ext-diff", "--no-textconv", "--binary",
                    "--no-renames", "HEAD", "--", relative)
        (output / "project.patch").write_bytes(patch)
        print(f"Unapproved project diagnostics: {output.relative_to(ROOT)}")
        print(patch.decode("utf-8", errors="replace"))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        message = f"Could not capture project diagnostics: {type(error).__name__}"
        (output / "diagnostic-error.txt").write_text(message + "\n")
        print(message, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
