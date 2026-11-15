#!/usr/bin/env python3
"""Record a command against a saved, unchanged source and package-resolution snapshot.

Outputs are created in a new directory. This runner never resolves packages,
formats source, regenerates fixtures, or substitutes historical test outputs.
An optional suite manifest enables strict Dart/Flutter machine-event accounting.
"""
import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone


def now():
    return datetime.now(timezone.utc).isoformat()


def encode(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def state(repo):
    return {
        "head": git(repo, "rev-parse", "HEAD").decode().strip(),
        "tree": git(repo, "rev-parse", "HEAD^{tree}").decode().strip(),
        "status": git(repo, "status", "--porcelain=v1", "--untracked-files=all").decode(),
        "source_changes": git(repo, "diff", "--name-only", "HEAD", "--", ".",
                              ":(exclude)docs/evidence/**").decode().splitlines(),
        "untracked_source": git(repo, "ls-files", "--others", "--exclude-standard", "--", ".",
                                ":(exclude)docs/evidence/**").decode().splitlines(),
    }


def snapshot(repo):
    names = {os.fsdecode(p) for p in git(repo, "ls-files", "-z").split(b"\0") if p}
    names = {p for p in names if not p.startswith("docs/evidence/")}
    for prefix in ("", "packages/quds_office_engine/", "packages/quds_office_editor/",
                   "packages/legacy_doc_parser/"):
        names.update(prefix + p for p in ("pubspec.lock", ".dart_tool/package_config.json",
                                          ".dart_tool/package_graph.json"))
    entries = {}
    for name in sorted(names):
        path = repo / name
        if path.is_symlink():
            data = os.fsencode(os.readlink(path))
            entries[name] = {"kind": "symlink", "size": len(data),
                             "sha256": hashlib.sha256(data).hexdigest()}
        elif path.is_file():
            entries[name] = {"kind": "file", "size": path.stat().st_size,
                             "sha256": digest(path)}
        else:
            entries[name] = {"kind": "missing_or_nonfile"}
    return {"at": now(), "count": len(entries), "entries": entries,
            "entries_sha256": hashlib.sha256(encode(entries)).hexdigest(),
            "selector": "All tracked paths except docs/evidence/**; root, Office engine/editor, "
                        "and legacy parser package locks/configs/graphs are included even if ignored."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--cwd", default=".")
    parser.add_argument("--suites", type=Path)
    parser.add_argument("--tool", type=Path, action="append", default=[])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    cwd = (repo / args.cwd).resolve()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not cwd.is_dir() or not cwd.is_relative_to(repo):
        parser.error("provide a command and a working directory within the repository")
    if output.exists() and any(output.iterdir()):
        parser.error("output directory must be empty")
    before_git = state(repo)
    if (before_git["head"] != args.head or before_git["source_changes"]
            or before_git["untracked_source"]):
        parser.error("requested saved source must be checked out without tracked source changes")
    suites, event_parser = None, None
    helper = repo / "docs/evidence/storage-delta-queue-20261114/run_delta_qualification.py"
    if args.suites:
        suites = [line.strip() for line in args.suites.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith("#")]
        if not suites or len(suites) != len(set(suites)):
            parser.error("suite manifest must contain unique repository-relative paths")
        if any(not (repo / p).is_file() or not (repo / p).resolve().is_relative_to(repo)
               for p in suites):
            parser.error("suite path is missing or outside repository")
        spec = importlib.util.spec_from_file_location("native_receipts", helper)
        event_parser = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(event_parser)
    tool_paths = [Path(__file__).resolve(), *[p.resolve() for p in args.tool]]
    if suites:
        tool_paths.append(helper)
    tool_hashes = lambda: {str(p): digest(p) for p in tool_paths}
    output.mkdir(parents=True, exist_ok=True)
    write = lambda name, value: (output / name).write_bytes(encode(value))
    if suites:
        (output / "suites.txt").write_text("\n".join(suites) + "\n")
    before, before_tools = snapshot(repo), tool_hashes()
    (output / "inputs-before.json.gz").write_bytes(gzip.compress(encode(before), mtime=0))
    write("command.json", {"argv": command, "cwd": str(cwd), "shell_display": shlex.join(command)})
    metadata = {"schema": 1, "started_at": now(), "repo": str(repo), "cwd": str(cwd),
                "before_git": before_git, "before_tools": before_tools,
                "platform": platform.platform(), "python": sys.version,
                "command": command, "suite_count": len(suites) if suites else None}
    write("metadata.json", metadata)
    started = time.monotonic()
    stdout_name = "stdout.jsonl" if suites else "stdout.log"
    with (output / stdout_name).open("wb") as stdout, (output / "stderr.log").open("wb") as stderr:
        try:
            result = subprocess.run(command, cwd=cwd, stdout=stdout, stderr=stderr, check=False)
            code = result.returncode
        except (OSError, KeyboardInterrupt) as error:
            code = 130 if isinstance(error, KeyboardInterrupt) else 127
            metadata["execution_error"] = repr(error)
    after, after_git, after_tools = snapshot(repo), state(repo), tool_hashes()
    (output / "inputs-after.json.gz").write_bytes(gzip.compress(encode(after), mtime=0))
    old, new = before["entries"], after["entries"]
    changes = {"added": sorted(new.keys() - old.keys()), "removed": sorted(old.keys() - new.keys()),
               "changed": sorted(p for p in old.keys() & new.keys() if old[p] != new[p])}
    stable = not any(changes.values()) and before_tools == after_tools and all(
        before_git[k] == after_git[k]
        for k in ("head", "tree", "source_changes", "untracked_source"))
    success = code == 0 and stable
    summary = None
    if suites:
        summary = event_parser.parse_machine(output / stdout_name, repo, suites)
        expected_paths = set(suites)
        summary["unexpected_suites"] = sorted({row["path"] for row in summary["suites"]}
                                              - expected_paths)
        summary["nonpassing_requested_suites"] = [
            row["path"] for row in summary["suites"]
            if row["path"] in expected_paths and row["result"] != "passed"]
        success = success and summary["done_success"] and not summary["missing_suites"] and not any(
            summary["totals"][k] for k in ("failed", "errors", "other_results", "skipped")) and not (
                summary["unexpected_suites"] or summary["nonpassing_requested_suites"])
        summary["qualification_success"] = success
        write("summary.json", summary)
    metadata.update({"finished_at": now(), "elapsed_seconds": time.monotonic() - started,
                     "returncode": code, "after_git": after_git, "after_tools": after_tools,
                     "input_count": before["count"], "input_changes": changes,
                     "inputs_and_commit_stable": stable, "qualification_success": success,
                     "before_entries_sha256": before["entries_sha256"],
                     "after_entries_sha256": after["entries_sha256"],
                     "scope_note": "Before/after source and resolution-input equality, not a hermetic "
                                   "cache snapshot or proof against transient writes. Exit success only "
                                   "qualifies the recorded command's scope."})
    write("metadata.json", metadata)
    write("artifacts-sha256.json", {p.name: {"sha256": digest(p), "size": p.stat().st_size}
                                   for p in sorted(output.iterdir()) if p.is_file()
                                   and p.name != "artifacts-sha256.json"})
    print(json.dumps({"output": str(output), "qualification_success": success,
                      "returncode": code, "inputs_and_commit_stable": stable,
                      "totals": summary["totals"] if summary else None}, indent=2))
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
