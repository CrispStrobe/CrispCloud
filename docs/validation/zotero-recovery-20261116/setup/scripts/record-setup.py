#!/usr/bin/env python3
"""Record exact local runtime and harness provenance after successful setup."""
from datetime import datetime, timezone
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--toolchain", type=Path, default=Path(__file__).resolve().parent)
arguments = parser.parse_args()
ROOT = arguments.toolchain.resolve()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    initial = json.loads((ROOT / "reconstruction-inputs.json").read_text())
    sdk = ROOT / "flutter-sdk"
    sdk_paths = [
        "bin/cache/dart-sdk/bin/dart",
        "bin/cache/artifacts/engine/linux-x64/flutter_tester",
        "bin/cache/flutter_tools.snapshot",
        "bin/cache/flutter.version.json",
        "bin/internal/engine.version",
    ]
    inputs = {}
    changes = []
    for path, sha in initial["inputs_sha256"].items():
        target = ROOT / path
        inputs[path] = {"sha256": digest(target), "text": target.read_text()}
        if inputs[path]["sha256"] != sha:
            changes.append(path)
    harnesses = {}
    for name, path in {
        "engine": "harness/quds_office_engine",
        "editor": "harness/quds_office_editor",
        "studio": "harness/quds_office_studio",
        "host": "crisp-host-harness",
    }.items():
        root = ROOT / path
        config = root / ".dart_tool/package_config.json"
        harnesses[name] = {
            "directory": str(root),
            "resolved_package_count": len(json.loads(config.read_text())["packages"]),
            "package_config_sha256": digest(config),
            "source_lib": str((root / "lib").resolve()),
            "source_test": str((root / "test").resolve()),
        }
    out = {
        "recorded_utc": datetime.now(timezone.utc).isoformat(),
        "source_receipt": initial["source_receipt"],
        "source_receipt_sha256": initial["source_receipt_sha256"],
        "workspace_rebase_from": initial["workspace_rebase_from"],
        "workspace_rebase_to": initial["workspace_rebase_to"],
        "framework_commit": subprocess.check_output(["git", "-C", str(sdk), "rev-parse", "HEAD"], text=True).strip(),
        "sdk_tracked_status": subprocess.check_output(["git", "-C", str(sdk), "status", "--porcelain", "--untracked-files=no"], text=True).strip(),
        "runtime": json.loads((sdk / "bin/cache/flutter.version.json").read_text()),
        "dart_version": subprocess.check_output([str(sdk / "bin/cache/dart-sdk/bin/dart"), "--version"], text=True).strip(),
        "sdk_artifacts": {path: {"bytes": (sdk / path).stat().st_size, "sha256": digest(sdk / path)} for path in sdk_paths},
        "harnesses": harnesses,
        "inputs": inputs,
        "inputs_changed_since_reconstruction": changes,
        "source_manifests_modified": False,
        "uses_github_actions": False,
        "resolution_logs": {path.name: {"bytes": path.stat().st_size, "sha256": digest(path)} for path in sorted((ROOT / "logs").glob("*")) if path.is_file()},
    }
    (ROOT / "setup-receipt-20261116.json").write_text(json.dumps(out, indent=2) + "\n")
    print(json.dumps({"harnesses": harnesses, "inputs_changed": changes, "sdk_tracked_status": out["sdk_tracked_status"]}, indent=2))


if __name__ == "__main__":
    main()
