#!/usr/bin/env python3
"""Qualify the actual CrispCloud Zotero host against its exact Quds source pin.

Reuse the actual host tests, including local saved-search routes, and vendor gates with a temporary analyzer graph
derived only from the genuine, resolved host harness. No CI is invoked.
"""

import argparse
import importlib.util
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urljoin, urlparse


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "zotero_host_qualification",
    HERE / "host-validation.py",
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=HERE.parents[2])
    parser.add_argument("--harness", type=Path, required=True)
    parser.add_argument("--quds-source", type=Path, required=True)
    parser.add_argument("--expected-quds", required=True)
    parser.add_argument("--output", type=Path, default=HERE / "final")
    args = parser.parse_args()
    repo, harness = args.repo.resolve(), args.harness.resolve()
    source_config = harness / ".dart_tool/package_config.json"
    config = json.loads(source_config.read_text())
    for entry in config["packages"]:
        name = entry["name"]
        if name == "crisp_cloud":
            root = repo
        elif name in runner.PACKAGES:
            root = repo / "packages" / name
        else:
            uri = urlparse(urljoin(source_config.as_uri(), entry["rootUri"]))
            if uri.scheme != "file" or uri.netloc:
                raise ValueError(f"Unsupported resolved package root for {name}")
            root = Path(unquote(uri.path)).resolve()
        if not root.is_dir():
            raise ValueError(f"Missing resolved package root for {name}: {root}")
        entry["rootUri"] = root.as_uri() + "/"
    target = repo / ".dart_tool/package_config.json"
    previous = target.read_bytes() if target.exists() else None
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(config, indent=2) + "\n")
    try:
        sys.argv = [
            sys.argv[0], "--repo", str(repo), "--harness", str(harness),
            "--quds-source", str(args.quds_source.resolve()),
            "--expected-quds", args.expected_quds,
            "--parser-baseline", "45ed126a6d7da0ecd80f3a765155f54008b278f3",
            "--expected-tests", "39",
            "--output", str(args.output.resolve()),
        ]
        return runner.main()
    finally:
        if previous is None:
            target.unlink(missing_ok=True)
        else:
            target.write_bytes(previous)


if __name__ == "__main__":
    raise SystemExit(main())
