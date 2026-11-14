#!/usr/bin/env python3
"""Run one pinned native suite cohort and retain auditable qualification receipts.

Usage: run_delta_qualification.py REPO OUTPUTDIR SUITES_MANIFEST
Manifest: newline-separated repo-relative paths, JSON list, or {"suites": [...]}.
The output directory must be empty. This never runs pub get or fixture generators.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone


def now():
    return datetime.now(timezone.utc).isoformat()


def encode(value):
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=True) + "\n").encode()


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def git_state(repo):
    return {
        "head": git(repo, "rev-parse", "HEAD").decode().strip(),
        "tree": git(repo, "rev-parse", "HEAD^{tree}").decode().strip(),
        "status": git(repo, "status", "--porcelain=v1", "--untracked-files=all").decode(),
    }


def snapshot(repo):
    names = {os.fsdecode(p) for p in git(repo, "ls-files", "-z").split(b"\0") if p}
    names = {p for p in names if not p.startswith("docs/evidence/")}
    names.update([".dart_tool/package_config.json", ".dart_tool/package_graph.json"])
    entries = {}
    for name in sorted(names):
        path = repo / name
        if path.is_symlink():
            data = os.fsencode(os.readlink(path))
            entries[name] = {"kind": "symlink", "size": len(data),
                             "sha256": hashlib.sha256(data).hexdigest()}
        elif path.is_file():
            entries[name] = {"kind": "file", "size": path.stat().st_size, "sha256": digest(path)}
        else:
            entries[name] = {"kind": "missing_or_nonfile"}
    return {"at": now(), "selector": "all tracked except docs/evidence/**, plus root package_config.json and package_graph.json",
            "count": len(entries), "entries_sha256": hashlib.sha256(encode(entries)).hexdigest(),
            "entries": entries}


def parse_machine(path, repo, expected):
    suites, tests, completed, errors, done = {}, {}, [], [], []
    ignored = {"non_json_lines": 0, "non_object_json_lines": 0}
    with path.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except ValueError:
                ignored["non_json_lines"] += 1
                continue
            if not isinstance(event, dict):
                ignored["non_object_json_lines"] += 1
                continue
            kind = event.get("type")
            if kind == "suite" and isinstance(event.get("suite"), dict):
                item = event["suite"]
                suites[item.get("id")] = item
            elif kind == "testStart" and isinstance(event.get("test"), dict):
                item = event["test"]
                tests[item.get("id")] = item
            elif kind == "testDone":
                completed.append(event)
            elif kind == "error":
                errors.append(event)
            elif kind == "done":
                done.append(event)
    def suite_path(suite_id):
        value = suites.get(suite_id, {}).get("path", "(unknown)")
        prefix = str(repo) + "/"
        if value.startswith("file://"):
            value = value[7:]
        return value[len(prefix):] if value.startswith(prefix) else value
    def blank(path):
        return {"path": path, "observed": False, "tests": 0, "passed": 0,
                "skipped": 0, "failed": 0, "other_results": 0, "errors": 0}
    rows = {path: blank(path) for path in expected}
    for suite_id in suites:
        name = suite_path(suite_id)
        rows.setdefault(name, blank(name))["observed"] = True
    hidden = 0
    for event in completed:
        if event.get("hidden", False):
            hidden += 1
            continue
        test = tests.get(event.get("testID"), {})
        name = suite_path(test.get("suiteID"))
        row = rows.setdefault(name, blank(name))
        row["tests"] += 1
        if event.get("skipped", False):
            row["skipped"] += 1
        elif event.get("result") == "success":
            row["passed"] += 1
        elif event.get("result") in ("failure", "error"):
            row["failed"] += 1
        else:
            row["other_results"] += 1
    for event in errors:
        name = suite_path(tests.get(event.get("testID"), {}).get("suiteID"))
        rows.setdefault(name, blank(name))["errors"] += 1
    for row in rows.values():
        row["result"] = ("failed" if row["failed"] or row["errors"] or row["other_results"]
                         else "not_observed" if not row["observed"]
                         else "no_visible_tests" if not row["tests"]
                         else "skipped" if row["skipped"] == row["tests"]
                         else "passed_with_skips" if row["skipped"] else "passed")
    totals = {key: sum(row[key] for row in rows.values())
              for key in ("tests", "passed", "skipped", "failed", "other_results", "errors")}
    return {"totals": totals, "suites": list(rows.values()), "errors": errors,
            "hidden_test_done": hidden, "done_events": done,
            "done_success": bool(done) and done[-1].get("success") is True,
            "missing_suites": [p for p in expected if not rows[p]["observed"]], **ignored}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path)
    parser.add_argument("outputdir", type=Path)
    parser.add_argument("suites_manifest", type=Path)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.outputdir.resolve()
    manifest = args.suites_manifest.resolve()
    raw = manifest.read_bytes()
    content = raw.decode("utf-8-sig")
    if content.lstrip().startswith(("[", "{")):
        suites = json.loads(content)
        suites = suites.get("suites") if isinstance(suites, dict) else suites
    else:
        suites = [line.strip() for line in content.splitlines()
                  if line.strip() and not line.lstrip().startswith("#")]
    if not isinstance(suites, list) or not suites or not all(isinstance(p, str) for p in suites):
        parser.error("manifest must contain a nonempty list of suite paths")
    if len(suites) != len(set(suites)):
        parser.error("manifest contains duplicate suites")
    for name in suites:
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or not name.endswith(".dart"):
            parser.error("suite must be a relative Dart file: " + name)
        if not (repo / path).is_file() or not (repo / path).resolve().is_relative_to(repo):
            parser.error("suite is missing or outside repository: " + name)
    launcher = repo.parent / "toolchain/run"
    if not launcher.is_file():
        parser.error("launcher not found: " + str(launcher))
    if output.exists() and any(output.iterdir()):
        parser.error("output directory must be empty")
    output.mkdir(parents=True, exist_ok=True)
    command = [str(launcher), "flutter", "test", "--no-pub", "--concurrency=1", "--machine", *suites]
    write = lambda name, value: (output / name).write_bytes(encode(value))
    (output / "suites-manifest.original").write_bytes(raw)
    write("command.json", {"argv": command, "cwd": str(repo), "shell_display": shlex.join(command)})
    before_git, before = git_state(repo), snapshot(repo)
    (output / "inputs-before.json.gz").write_bytes(gzip.compress(encode(before), mtime=0))
    metadata = {"repo": str(repo), "manifest": str(manifest), "manifest_sha256": hashlib.sha256(raw).hexdigest(),
                "suite_count": len(suites), "started_at": now(), "command": command, "before_git": before_git,
                "runner_sha256": digest(Path(__file__).resolve()), "launcher_sha256": digest(launcher)}
    write("metadata.json", metadata)
    started = time.monotonic()
    with (output / "stdout.jsonl").open("wb") as stdout, (output / "stderr.log").open("wb") as stderr:
        try:
            result = subprocess.run(command, cwd=repo, stdout=stdout, stderr=stderr, check=False)
            returncode = result.returncode
        except (OSError, KeyboardInterrupt) as error:
            returncode = 130 if isinstance(error, KeyboardInterrupt) else 127
            metadata["execution_error"] = repr(error)
    metadata.update({"finished_at": now(), "elapsed_seconds": time.monotonic() - started, "returncode": returncode})
    after_git, after = git_state(repo), snapshot(repo)
    (output / "inputs-after.json.gz").write_bytes(gzip.compress(encode(after), mtime=0))
    old, new = before["entries"], after["entries"]
    changes = {"added": sorted(new.keys() - old.keys()), "removed": sorted(old.keys() - new.keys()),
               "changed": sorted(p for p in old.keys() & new.keys() if old[p] != new[p])}
    stable = not any(changes.values()) and all(before_git[k] == after_git[k] for k in ("head", "tree"))
    metadata.update({"after_git": after_git, "input_changes": changes, "inputs_and_commit_stable": stable,
                     "git_status_unchanged": before_git["status"] == after_git["status"]})
    parsed = parse_machine(output / "stdout.jsonl", repo, suites)
    runtime_success = (returncode == 0 and parsed["done_success"] and not parsed["missing_suites"]
                       and not any(parsed["totals"][k] for k in ("failed", "errors", "other_results")))
    parsed.update({"runtime_success": runtime_success, "qualification_success": runtime_success and stable,
                   "input_stability_note": "Compares before/after hashes; does not prove absence of transient writes."})
    write("metadata.json", metadata)
    write("summary.json", parsed)
    write("artifacts-sha256.json", {p.name: {"sha256": digest(p), "size": p.stat().st_size}
                                   for p in sorted(output.iterdir()) if p.is_file()})
    print(json.dumps({"outputdir": str(output), "qualification_success": parsed["qualification_success"],
                      "totals": parsed["totals"], "returncode": returncode}, indent=2))
    return 0 if parsed["qualification_success"] else 1


if __name__ == "__main__":
    sys.exit(main())
