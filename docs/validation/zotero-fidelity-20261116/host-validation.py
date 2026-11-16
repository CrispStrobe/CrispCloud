#!/usr/bin/env python3
"""Qualify the actual host Zotero sources against an exact vendored Quds pin.

The caller prepares a genuine, resolved Flutter harness. This script verifies
that its package roots link to this checkout; it never supplies replacement
implementations or edits production dependency constraints. HEAD may advance
while evidence is written, but the measured sources and vendor manifest must
remain byte-identical throughout qualification.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urljoin, urlparse


PACKAGES = (
    "quds_office_engine",
    "quds_office_editor",
    "quds_reports",
    "legacy_doc_parser",
)
TESTS = (
    "test/office_zotero_citing_transport_test.dart",
    "test/office_zotero_test.dart",
    "test/office_zotero_ribbon_test.dart",
)
ANALYSIS_TARGETS = (
    "lib/services/office_zotero.dart",
    "lib/services/office_zotero_transport.dart",
    "lib/l10n/office_zotero_strings.dart",
    "lib/l10n/office_editor_strings.dart",
    "lib/widgets/office_editor_ribbon.dart",
    *TESTS,
)
PARSER_PREFIX = "packages/legacy_doc_parser/"


def now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def aggregate(value: object) -> str:
    return sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def git(repo: Path, *arguments: str) -> str:
    return subprocess.check_output(["git", *arguments], cwd=repo, text=True).strip()


def source_snapshot(repo: Path) -> dict[str, str]:
    files = {repo / name for name in TESTS}
    for relative in ("lib", *(f"packages/{name}/lib" for name in PACKAGES)):
        files.update(path for path in (repo / relative).rglob("*") if path.is_file())
    for base in (repo, *(repo / "packages" / name for name in PACKAGES)):
        for name in ("pubspec.yaml", "pubspec.lock", "analysis_options.yaml"):
            if (base / name).is_file():
                files.add(base / name)
    return {
        str(path.relative_to(repo)): sha256(path.read_bytes())
        for path in sorted(files)
    }


def changed(before: dict, after: dict) -> list[str]:
    return [key for key in sorted(before.keys() | after.keys()) if before.get(key) != after.get(key)]


def manifest_snapshot(repo: Path) -> dict:
    raw = (repo / "tool/office_fidelity_manifest.json").read_bytes()
    manifest = json.loads(raw)
    return {
        "sha256": sha256(raw),
        "source_repository": manifest["source_repository"],
        "source_branch": manifest["source_branch"],
        "source_commit": manifest["source_commit"],
        "managed_file_count": len(manifest["files"]),
        "managed_inventory_sha256": aggregate(manifest["files"]),
        "standalone_sources": manifest["standalone_sources"],
    }


def resolve_uri(config: Path, uri: str) -> Path:
    value = urlparse(urljoin(config.as_uri(), uri))
    if value.scheme != "file" or value.netloc:
        raise ValueError(f"Unsupported local package root: {uri}")
    return Path(unquote(value.path)).resolve()


def inspect_graph(config: Path, repo: Path) -> dict:
    graph = json.loads(config.read_text())
    entries = {entry["name"]: entry for entry in graph["packages"]}
    roots = {}
    for name, expected in {
        "crisp_cloud": repo / "lib",
        **{name: repo / "packages" / name / "lib" for name in PACKAGES},
    }.items():
        entry = entries[name]
        root = resolve_uri(config, entry["rootUri"])
        actual = (root / entry.get("packageUri", "lib/")).resolve()
        if not actual.samefile(expected):
            raise ValueError(f"{name} resolves to {actual}, expected actual source {expected}")
        roots[name] = {"root": str(root), "library": str(actual)}
    return {
        "path": str(config),
        "sha256": sha256(config.read_bytes()),
        "package_count": len(entries),
        "actual_source_roots": roots,
    }


def dependency_inputs(repo: Path, harness: Path) -> dict:
    inputs = {}
    for name, base in {
        "harness": harness,
        **{f"harness/packages/{name}": harness / "packages" / name for name in PACKAGES},
    }.items():
        for filename in ("pubspec.yaml", "pubspec.lock"):
            path = base / filename
            if path.is_file():
                raw = path.read_bytes()
                inputs[f"{name}/{filename}"] = {
                    "sha256": sha256(raw),
                    "text": raw.decode(),
                }
    return {
        "inputs": inputs,
        "harness_graph": inspect_graph(harness / ".dart_tool/package_config.json", repo),
        "analysis_graph": inspect_graph(repo / ".dart_tool/package_config.json", repo),
    }


def parser_proof(repo: Path, baseline: str) -> dict:
    original_raw = subprocess.check_output(
        ["git", "show", f"{baseline}:tool/office_fidelity_manifest.json"], cwd=repo
    )
    original = json.loads(original_raw)
    current = json.loads((repo / "tool/office_fidelity_manifest.json").read_bytes())
    old = {k: v for k, v in original["files"].items() if k.startswith(PARSER_PREFIX)}
    new = {k: v for k, v in current["files"].items() if k.startswith(PARSER_PREFIX)}
    observed = {path: sha256((repo / path).read_bytes()) for path in new}
    return {
        "baseline_host_commit": baseline,
        "baseline_manifest_sha256": sha256(original_raw),
        "source_before": original["standalone_sources"][PARSER_PREFIX[:-1]],
        "source_after": current["standalone_sources"][PARSER_PREFIX[:-1]],
        "file_count_before": len(old),
        "file_count_after": len(new),
        "inventory_sha256_before": aggregate(old),
        "inventory_sha256_after": aggregate(new),
        "source_pin_unchanged": original["standalone_sources"] == current["standalone_sources"],
        "inventory_unchanged": old == new,
        "actual_bytes_match_inventory": observed == new,
        "changed_paths": changed(old, new),
        "mismatched_actual_paths": changed(new, observed),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--harness", required=True, type=Path)
    parser.add_argument("--flutter-root", type=Path, default=os.environ.get("FLUTTER_ROOT"))
    parser.add_argument("--quds-source", required=True, type=Path,
                        help="Immutable checkout/archive of the exact expected Quds pin")
    parser.add_argument("--expected-quds", required=True)
    parser.add_argument("--parser-baseline", default="fe22a0458acfa90c0cce457d20fecbaa85a260e6")
    parser.add_argument("--expected-tests", type=int, default=37)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    if args.flutter_root is None:
        parser.error("--flutter-root or FLUTTER_ROOT is required")
    repo, harness, flutter, output, quds = (
        value.resolve() for value in
        (args.repo, args.harness, args.flutter_root, args.output, args.quds_source)
    )
    output.mkdir(parents=True, exist_ok=True)
    dart = flutter / "bin/cache/dart-sdk/bin/dart"
    manifest_before = manifest_snapshot(repo)
    if manifest_before["source_commit"] != args.expected_quds:
        parser.error("The current vendor manifest does not match --expected-quds")
    source_before = source_snapshot(repo)
    write_json(output / "host-source-before.json", source_before)
    proof = parser_proof(repo, args.parser_baseline)
    write_json(output / "standalone-parser-proof.json", proof)
    receipt = {
        "schema_version": 1,
        "repository": "https://github.com/CrispStrobe/CrispCloud",
        "started_at_utc": now(),
        "head_at_start": git(repo, "rev-parse", "HEAD"),
        "head_is_informational": True,
        "vendor_manifest_before": manifest_before,
        "source_file_count": len(source_before),
        "source_inventory_before": "host-source-before.json",
        "source_aggregate_sha256_before": aggregate(source_before),
        "script_sha256": sha256(Path(__file__).read_bytes()),
        "runtime": json.loads((flutter / "bin/cache/flutter.version.json").read_text()),
        "environment": {
            name: os.environ[name] for name in
            ("FLUTTER_ROOT", "PUB_CACHE", "TMPDIR", "XDG_CONFIG_HOME", "CI",
             "FLUTTER_SUPPRESS_ANALYTICS", "DART_SUPPRESS_ANALYTICS")
            if name in os.environ
        },
        "tests": list(TESTS),
        "expected_test_count": args.expected_tests,
        "analysis_targets": list(ANALYSIS_TARGETS),
        "steps": [],
        "limitations": [
            "Focused genuine host dependency graph, not a full native application build or full production dependency resolution.",
            "Test clients and credential stores are test doubles; no live Zotero desktop, private account, real OS keychain or native Word refresh acceptance.",
            "Canonical engine/editor tests are qualified separately and are not counted as host test executions.",
            "No GitHub Actions queries, waits or reruns.",
        ],
    }

    def run(name: str, command: list[str], cwd: Path) -> None:
        path = output / f"host-{name}.log"
        started = now()
        with path.open("w") as log:
            result = subprocess.run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
        receipt["steps"].append({
            "name": name, "command": command, "cwd": str(cwd),
            "started_at_utc": started, "completed_at_utc": now(),
            "exit_code": result.returncode, "log": path.name,
            "log_sha256": sha256(path.read_bytes()),
        })
        if result.returncode:
            raise RuntimeError(f"{name} failed with exit {result.returncode}; see {path}")

    error = None
    try:
        if not (proof["source_pin_unchanged"] and proof["inventory_unchanged"]
                and proof["actual_bytes_match_inventory"]):
            raise RuntimeError("Standalone parser changed; inspect standalone-parser-proof.json")
        inspect_graph(harness / ".dart_tool/package_config.json", repo)
        run("pub-get", [str(dart), "pub", "get", "--offline", "--enforce-lockfile"], harness)
        inputs = dependency_inputs(repo, harness)
        write_json(output / "host-dependency-inputs.json", inputs)
        receipt["dependency_inputs"] = "host-dependency-inputs.json"
        receipt["dependency_inputs_sha256"] = sha256((output / "host-dependency-inputs.json").read_bytes())
        receipt["dependency_package_count"] = inputs["harness_graph"]["package_count"]
        run("vendor-verify", [sys.executable, "tool/verify_office_fidelity.py", "--source", str(quds)], repo)
        run("vendor-verify-tracked", [sys.executable, "tool/verify_office_fidelity.py", "--source", str(quds), "--require-tracked"], repo)
        # Use the already provisioned official Flutter tool with its matching
        # Dart SDK, avoiding concurrent shell-wrapper stamp-file updates.
        run("tests", [str(dart), str(flutter / "bin/cache/flutter_tools.snapshot"),
                      "test", "--no-pub", "--concurrency=1",
                      "--reporter", "expanded", *(str(repo / name) for name in TESTS)], harness)
        match = re.search(r"\+(\d+): All tests passed!", (output / "host-tests.log").read_text())
        receipt["passed_test_count"] = int(match.group(1)) if match else None
        if receipt["passed_test_count"] != args.expected_tests:
            raise RuntimeError("The executed host test count did not match the expected cohort")
        run("analysis", [str(dart), "analyze", "--fatal-infos", *ANALYSIS_TARGETS], repo)
        run("format", [str(dart), "format", "--output=none", "--set-exit-if-changed", *ANALYSIS_TARGETS], repo)
        run("whitespace", ["git", "diff", "--check"], repo)
    except Exception as failure:
        error = str(failure)
    finally:
        source_after = source_snapshot(repo)
        manifest_after = manifest_snapshot(repo)
        write_json(output / "host-source-after.json", source_after)
        receipt.update({
            "completed_at_utc": now(),
            "head_at_completion": git(repo, "rev-parse", "HEAD"),
            "vendor_manifest_after": manifest_after,
            "vendor_manifest_unchanged": manifest_before == manifest_after,
            "source_inventory_after": "host-source-after.json",
            "source_aggregate_sha256_after": aggregate(source_after),
            "source_unchanged": source_before == source_after,
            "source_changed_paths": changed(source_before, source_after),
            "standalone_parser_proof": "standalone-parser-proof.json",
        })
        if source_before != source_after or manifest_before != manifest_after:
            error = (error + "; " if error else "") + "Qualified source or manifest changed during execution"
        receipt["status"] = "passed" if error is None else "failed"
        receipt["error"] = error
        write_json(output / "host-validation-receipt.json", receipt)
    print(json.dumps({key: receipt.get(key) for key in
                      ("status", "passed_test_count", "source_file_count", "source_unchanged",
                       "vendor_manifest_unchanged", "source_changed_paths", "error")}, indent=2))
    return 0 if error is None else 1


if __name__ == "__main__":
    raise SystemExit(main())
