#!/usr/bin/env python3
"""Recreate the saved terminal dependency graph by rebasing paths only."""

import argparse
from pathlib import Path


RECORDED_WORKSPACE = "/workspace/scratch/7b8555dd0115"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--toolchain", type=Path)
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    toolchain = (args.toolchain or workspace / "zotero-toolchain").resolve()
    source = workspace / "CrispCloud"
    harness = toolchain / "crisp-terminal-harness"
    host = toolchain / "crisp-host-harness"
    for package in ("quds_office_engine", "quds_office_editor", "quds_reports", "legacy_doc_parser"):
        if not (host / "packages" / package / "pubspec.yaml").is_file():
            parser.error(f"Reconstruct the saved host graph first: {host / 'packages' / package}")
    if toolchain.parent != workspace:
        parser.error("The saved relative path lock expects the toolchain directory directly inside the workspace.")
    harness.mkdir(parents=True, exist_ok=True)
    evidence = Path(__file__).resolve().parent
    for name in ("pubspec.yaml", "pubspec.lock"):
        text = (evidence / name).read_text()
        text = text.replace(RECORDED_WORKSPACE + "/zotero-toolchain", str(toolchain))
        text = text.replace(RECORDED_WORKSPACE, str(workspace))
        (harness / name).write_text(text)
    for name in ("lib", "test", "analysis_options.yaml"):
        target = harness / name
        actual = source / name
        if target.is_symlink():
            if target.resolve() != actual.resolve():
                parser.error(f"Existing link points elsewhere: {target}")
        elif target.exists():
            parser.error(f"Refusing to replace existing path: {target}")
        else:
            target.symlink_to(actual, target_is_directory=actual.is_dir())
    print(f"Prepared {harness}; resolve with the saved SDK and --enforce-lockfile.")


if __name__ == "__main__":
    main()
