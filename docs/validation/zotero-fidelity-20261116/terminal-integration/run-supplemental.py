#!/usr/bin/env python3
"""Run the disjoint terminal UI/transport supplement with the full locked graph.

The application library is an exact isolated copy; tests and local package
dependencies are actual canonical sources. Native build hooks stay enabled.
No production file, dependency constraint, import or hook is replaced.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse


TESTS = [
    "ssh_agent_widget_test.dart",
    "terminal_mount_localization_test.dart",
    "ssh_terminal_transport_test.dart",
    "ssh_tmux_panel_lifecycle_test.dart",
    "tmux_control_workspace_test.dart",
]
sys.dont_write_bytecode = True


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True,
                        help="Canonical source map recorded before the full production bundle attempt.")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "supplemental")
    parser.add_argument("--timeout", type=int, default=150)
    args = parser.parse_args()
    source, project, output = args.source.resolve(), args.project.resolve(), args.output.resolve()
    sdk = Path(os.environ["FLUTTER_ROOT"]).resolve()
    dart, flutter = sdk / "bin/cache/dart-sdk/bin/dart", sdk / "bin/cache/flutter_tools.snapshot"
    output.mkdir(parents=True, exist_ok=True)
    helper_spec = importlib.util.spec_from_file_location("terminal_evidence", Path(__file__).with_name("run-checks.py"))
    helper = importlib.util.module_from_spec(helper_spec)
    helper_spec.loader.exec_module(helper)
    if set(TESTS) & set(helper.TESTS):
        parser.error("Supplemental suites must not overlap the focused core selection.")

    def git(*args):
        return subprocess.check_output(["git", "-C", str(source), *args], text=True).strip()

    baseline = json.loads(args.baseline.read_text())
    paths = set(baseline)
    pending = [source / "test" / name for name in TESTS]
    while pending:
        path = pending.pop().resolve()
        relative = str(path.relative_to(source))
        if relative in paths:
            continue
        paths.add(relative)
        for directive in re.findall(r"\b(?:import|export|part)\s+([^;]*);", path.read_text()):
            for uri in re.findall(r"['\"]([^'\"]+)['\"]", directive):
                if ":" not in uri:
                    imported = (path.parent / uri).resolve()
                    if imported.is_file() and imported.is_relative_to(source / "test"):
                        pending.append(imported)

    def snapshot():
        hashes = {name: digest((source / name).read_bytes()) for name in sorted(paths)}
        actual = {
            "lib/" + str(path.relative_to(project / "lib")): digest(path.read_bytes())
            for path in sorted((project / "lib").rglob("*")) if path.is_file()
        }
        canonical_library = {name: sha for name, sha in hashes.items() if name.startswith("lib/")}
        differences = [name for name in sorted(canonical_library.keys() | actual.keys())
                       if canonical_library.get(name) != actual.get(name)]
        return {
            "files": len(hashes), "aggregate_sha256": digest(encoded(hashes)),
            "sha256_by_path": hashes, "isolated_library_files": len(actual),
            "isolated_library_sha256_by_path": actual,
            "isolated_library_matches_canonical": not differences,
            "isolated_library_differences": differences,
        }

    def dependency_inputs():
        values = {}
        for name in ("pubspec.yaml", "pubspec.lock", ".dart_tool/package_config.json"):
            path = project / name
            values[name] = {"sha256": digest(path.read_bytes()), "text": path.read_text()}
        return values

    test_link = project / "test"
    created_test_link = False
    if not test_link.exists() and not test_link.is_symlink():
        test_link.symlink_to(source / "test", target_is_directory=True)
        created_test_link = True
    if test_link.resolve() != source / "test":
        parser.error("The full project test directory must point to the actual canonical tests.")
    before = snapshot()
    if not before["isolated_library_matches_canonical"]:
        (output / "source-before.json").write_bytes(encoded(before))
        parser.error("The isolated application library differs from the actual canonical source.")
    dependencies = dependency_inputs()
    for name in ("pubspec.yaml", "pubspec.lock"):
        if (project / name).read_bytes() != (source / name).read_bytes():
            parser.error("Full production manifests and lock must be byte-identical: " + name)
        (output / name).write_bytes((project / name).read_bytes())
    config_path = project / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    roots = {
        entry["name"]: Path(unquote(urlparse(urljoin(config_path.as_uri(), entry["rootUri"])).path)).resolve()
        for entry in config["packages"]
    }
    if roots["dartssh2"] != source / "packages/dartssh2":
        parser.error("The full graph must resolve production vendored dartssh2.")
    (output / "source-before.json").write_bytes(encoded(before))
    command = [str(dart), str(flutter), "test", "--no-pub", "--concurrency=1", "--reporter=json",
               *["test/" + name for name in TESTS]]
    record = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": git("rev-parse", "HEAD"),
        "source_tree": git("rev-parse", "HEAD^{tree}"),
        "source": str(source), "project": str(project), "tests": TESTS,
        "command": command, "timeout_seconds": args.timeout,
        "source_before": {key: value for key, value in before.items()
                          if key not in ("sha256_by_path", "isolated_library_sha256_by_path")},
        "canonical_test_sha256": {"test/" + name: before["sha256_by_path"]["test/" + name] for name in TESTS},
        "tests_resolve_to_canonical": test_link.resolve() == source / "test",
        "created_isolated_test_symlink": created_test_link,
        "source_baseline_file": str(args.baseline.resolve()),
        "source_baseline_sha256": digest(args.baseline.read_bytes()),
        "baseline_sources_still_match": all(before["sha256_by_path"].get(name) == sha for name, sha in baseline.items()),
        "dependency_inputs": dependencies,
        "production_manifests_byte_identical": True,
        "resolved_package_count": len(roots),
        "actual_dartssh2_root": str(roots["dartssh2"]),
        "runtime": json.loads((sdk / "bin/cache/flutter.version.json").read_text()),
        "runner_sha256": digest(Path(__file__).read_bytes()),
        "counter_helper_sha256": digest(Path(__file__).with_name("run-checks.py").read_bytes()),
        "uses_github_actions": False, "stubs_or_hook_overrides": False,
        "private_connections_or_credentials": False,
        "disjoint_from_focused_core": True, "full_native_application": False,
    }

    def save():
        (output / "receipt.json").write_bytes(encoded(record))

    save()
    started = time.monotonic()
    log_path = output / "terminal-supplemental.log"
    try:
        with log_path.open("wb") as stream:
            process = subprocess.Popen(command, cwd=project, stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                record["exit_code"] = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                record.update(timed_out=True, exit_code=process.returncode)
    except OSError as error:
        record.update(execution_error=str(error), exit_code=None)
    finally:
        record["seconds"] = round(time.monotonic() - started, 3)
        log = log_path.read_text(errors="replace") if log_path.is_file() else ""
        record.update(helper.count_tests(log))
        record["log"] = log_path.name
        record["log_sha256"] = digest(log_path.read_bytes()) if log_path.is_file() else None
        after = snapshot()
        (output / "source-after.json").write_bytes(encoded(after))
        record["source_after"] = {key: value for key, value in after.items()
                                  if key not in ("sha256_by_path", "isolated_library_sha256_by_path")}
        record["source_unchanged"] = before == after
        record["dependencies_unchanged"] = dependencies == dependency_inputs()
        record["all_tests_passed"] = (
            record["exit_code"] == 0 and record["test_protocol_success"]
            and record["failed_tests"] == 0 and record["skipped_tests"] == 0
            and record["passed_tests"] > 0 and record["duplicate_visible_test_identities"] == 0
            and set(record["counts_by_file"]) == set(TESTS)
        )
        record["qualified"] = all(record[key] for key in (
            "source_unchanged", "dependencies_unchanged", "all_tests_passed",
            "baseline_sources_still_match", "tests_resolve_to_canonical",
        ))
        record["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        if created_test_link and test_link.is_symlink() and test_link.resolve() == source / "test":
            test_link.unlink()
            record["isolated_test_symlink_restored"] = True
        save()
    print(json.dumps({key: record[key] for key in (
        "qualified", "source_unchanged", "dependencies_unchanged", "all_tests_passed",
        "passed_tests", "failed_tests", "skipped_tests", "seconds",
    )}), flush=True)
    return 0 if record["qualified"] else 1


if __name__ == "__main__":
    sys.exit(main())
