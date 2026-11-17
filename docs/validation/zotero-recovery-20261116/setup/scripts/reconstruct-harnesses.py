#!/usr/bin/env python3
"""Reconstruct recorded genuine Zotero test graphs; only paths are rebased."""
import argparse
import hashlib
import json
import os
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--toolchain", type=Path, default=Path(__file__).resolve().parent)
parser.add_argument("--workspace", type=Path)
arguments = parser.parse_args()
ROOT = arguments.toolchain.resolve()
WORKSPACE = (arguments.workspace or ROOT.parent).resolve()
QUDS = WORKSPACE / "quds_office_suite"
CRISP = WORKSPACE / "CrispCloud"
OLD = "/workspace/scratch/d13d764c3646"


def rebase(text):
    return text.replace(OLD + "/zotero-toolchain", str(ROOT)).replace(OLD, str(WORKSPACE))


def link(target, source):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        assert target.resolve() == source.resolve(), (target, source)
    elif target.exists():
        raise ValueError(f"Refusing to replace existing path {target}")
    else:
        target.symlink_to(source, target_is_directory=source.is_dir())


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    for name in ["logs", "tmp", "config", "pub-cache"]:
        (ROOT / name).mkdir(exist_ok=True)
    receipt = json.loads((QUDS / "docs/validation/zotero-citing-20261115/setup-receipt.json").read_text())
    inputs = {}
    for name, value in receipt["harnesses"].items():
        folder = Path(rebase(value["directory"]))
        folder.mkdir(parents=True, exist_ok=True)
        for filename, key in [("pubspec.yaml", "manifest_text"), ("pubspec.lock", "lockfile_text")]:
            payload = rebase(value[key])
            (folder / filename).write_text(payload)
            inputs[str((folder / filename).relative_to(ROOT))] = hashlib.sha256(payload.encode()).hexdigest()
        for target, source in value["source_links"].items():
            link(folder / target, Path(rebase(source)))
    for path, value in receipt["supporting_package_manifests"].items():
        target = ROOT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rebase(value))
        inputs[path] = hashlib.sha256(target.read_bytes()).hexdigest()
    for name in ["quds_reports", "legacy_doc_parser"]:
        source = QUDS / "packages" / name
        target = ROOT / "harness" / name
        for item in source.iterdir():
            if item.name not in {"pubspec.yaml", "pubspec.lock", ".dart_tool", "build"}:
                link(target / item.name, item)
    # The delivered host receipt includes the final full host test graph.
    host_inputs = json.loads((CRISP / "docs/validation/zotero-citing-20261115/host-dependency-inputs.json").read_text())["inputs"]
    for path, value in host_inputs.items():
        target = ROOT / "crisp-host-harness" / path.removeprefix("harness/")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rebase(value["text"]))
        inputs[str(target.relative_to(ROOT))] = hashlib.sha256(target.read_bytes()).hexdigest()
    for source in (CRISP / "test").iterdir():
        target = ROOT / "crisp-host-harness/test" / source.name
        if not target.exists():
            link(target, source)
    env = "\n".join([
        f"export FLUTTER_ROOT='{ROOT / 'flutter-sdk'}'",
        f"export PUB_CACHE='{ROOT / 'pub-cache'}'",
        f"export TMPDIR='{ROOT / 'tmp'}'",
        f"export XDG_CONFIG_HOME='{ROOT / 'config'}'",
        'export PATH="$FLUTTER_ROOT/bin:$PATH"',
        'export CI=true FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true',
        "",
    ])
    (ROOT / "env.sh").write_text(env)
    (ROOT / "reconstruction-inputs.json").write_text(json.dumps({
        "source_receipt": str(QUDS / "docs/validation/zotero-citing-20261115/setup-receipt.json"),
        "source_receipt_sha256": hashlib.sha256((QUDS / "docs/validation/zotero-citing-20261115/setup-receipt.json").read_bytes()).hexdigest(),
        "workspace_rebase_from": OLD,
        "workspace_rebase_to": str(WORKSPACE),
        "source_manifests_modified": False,
        "inputs_sha256": inputs,
    }, indent=2) + "\n")
    print("Reconstructed engine, editor, Studio and host harness manifests/locks; canonical sources are symlinked.")


if __name__ == "__main__":
    main()
