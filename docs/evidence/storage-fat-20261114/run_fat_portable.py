"""Copy beside the prepared app-validation/ and flutter/ runtime directories.

The sibling CrispCloud/ repository remains the authoritative source checkout.
The evidence copy preserves the exact helper bytes executed for qualification.
"""

from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--label", required=True)
parser.add_argument("--output-dir", type=Path, required=True)
parser.add_argument("--source-revision")
args = parser.parse_args()
runtime = Path(__file__).resolve().parent
app = runtime / "app-validation"
primary = runtime.parent / "CrispCloud"
dart = runtime / "flutter/bin/cache/dart-sdk/bin/dart"
output = args.output_dir.resolve()
output.mkdir(parents=True, exist_ok=True)
sha = lambda data: hashlib.sha256(data).hexdigest()
paths = {
    "pubspec.yaml",
    "pubspec.lock",
    "lib/services/archive_types.dart",
    "lib/services/archive_fat_reader.dart",
    "lib/services/archive_disk_image_reader.dart",
    "lib/services/archive_slice_source.dart",
    "lib/services/disk_partition_inspector.dart",
    "test/support/archive_fat_reference_data.dart",
    "test/support/archive_fat_web_acceptance.dart",
    "test/support/archive_disk_image_fixture.dart",
    "test/support/disk_partition_fixture.dart",
    "test/fixtures/archives/fat-reference-manifest.json",
    "docs/evidence/storage-fat-20261114/run_fat_portable.py",
}
pending = [path for path in paths if path.endswith(".dart")]
while pending:
    current = pending.pop()
    text = (app / current).read_text()
    for declaration in re.findall(r"(?:import|export|part)\s+([^;]+);", text):
        for target in re.findall(r"'([^']+\.dart)'", declaration):
            if target.startswith("package:crisp_cloud/"):
                dependency = "lib/" + target[len("package:crisp_cloud/"):]
            elif ":" not in target:
                dependency = str(((app / current).parent / target).resolve().relative_to(app))
            else:
                continue
            if dependency not in paths:
                paths.add(dependency)
                pending.append(dependency)
paths = sorted(paths)
before = {name: sha((app / name).read_bytes()) for name in paths}
for name, digest in before.items():
    if sha((primary / name).read_bytes()) != digest:
        raise SystemExit("Validation source differs from primary: " + name)
    if args.source_revision:
        revision_bytes = subprocess.check_output(
            ["git", "show", args.source_revision + ":" + name], cwd=primary
        )
        if sha(revision_bytes) != digest:
            raise SystemExit("Validation source differs from pinned revision: " + name)

receipt = {
    "schema": 1,
    "started_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "source_revision": args.source_revision,
    "cwd": str(app),
    "dart": subprocess.check_output([str(dart), "--version"], text=True).strip(),
    "node": subprocess.check_output(["node", "--version"], text=True).strip(),
    "source_sha256": before,
    "package_config_sha256": sha((app / ".dart_tool/package_config.json").read_bytes()),
    "helper_sha256": sha(Path(__file__).read_bytes()),
    "scope": "Dart VM and actual dart2js JavaScript executed under Node; no browser-engine or WebAssembly qualification.",
    "commands": [],
    "results": {},
}
javascript = runtime / (args.label + ".js")
commands = [
    ("vm", [str(dart), "--packages=.dart_tool/package_config.json", "test/support/archive_fat_web_acceptance.dart"]),
    ("js-compile", [str(dart), "compile", "js", "-O2", "--packages=.dart_tool/package_config.json", "test/support/archive_fat_web_acceptance.dart", "-o", str(javascript)]),
    ("js", ["node", "-e", "globalThis.self = globalThis; require(process.argv[1]);", str(javascript)]),
]
success = False
try:
    for kind, command in commands:
        log = output / (args.label + "-" + kind + ".log")
        with log.open("w") as stream:
            completed = subprocess.run(command, cwd=app, stdout=stream, stderr=subprocess.STDOUT)
        receipt["commands"].append(
            {"kind": kind, "command": command, "exit_code": completed.returncode,
             "log": log.name, "log_sha256": sha(log.read_bytes())}
        )
        if completed.returncode:
            raise RuntimeError("Portable validation failed: " + kind)
        if kind in ("vm", "js"):
            receipt["results"][kind] = json.loads(log.read_text())
    receipt["vm_js_results_identical"] = receipt["results"]["vm"] == receipt["results"]["js"]
    if not receipt["vm_js_results_identical"]:
        raise RuntimeError("VM and JavaScript acceptance results differ")
    receipt["javascript"] = {"bytes": javascript.stat().st_size, "sha256": sha(javascript.read_bytes())}
    receipt["source_unchanged_and_primary_matches"] = all(
        sha((app / name).read_bytes()) == digest
        and sha((primary / name).read_bytes()) == digest
        for name, digest in before.items()
    )
    if not receipt["source_unchanged_and_primary_matches"]:
        raise RuntimeError("Acceptance input sources changed during qualification")
    success = True
finally:
    receipt["success"] = success
    receipt["finished_at_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (output / (args.label + "-receipt.json")).write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n")
print(json.dumps({"success": True, "groups_each_runtime": len(receipt["results"]["vm"]["groups"]), "checks_each_runtime": receipt["results"]["vm"]["checks"], "source_revision": args.source_revision}))
