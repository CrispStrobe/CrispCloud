#!/usr/bin/env python3
"""Run the focused, fixture-only terminal integration checks after reconciliation."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


TESTS = [
    "terminal_pane_layout_test.dart",
    "terminal_arrangements_test.dart",
    "terminal_arrangements_dialog_test.dart",
    "ssh_config_import_test.dart",
    "ssh_config_import_dialog_test.dart",
    "terminal_key_bindings_test.dart",
    "terminal_user_input_test.dart",
    "terminal_broadcast_test.dart",
    "ssh_jump_transport_test.dart",
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--harness", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    source = args.source.resolve()
    harness = (args.harness or source.parent / "zotero-toolchain/crisp-terminal-expanded-harness").resolve()
    output = args.output.resolve()
    sdk = Path(os.environ["FLUTTER_ROOT"]).resolve()
    dart = sdk / "bin/cache/dart-sdk/bin/dart"
    flutter = sdk / "bin/cache/flutter_tools.snapshot"
    for name in ("lib", "test"):
        if (harness / name).resolve() != source / name:
            parser.error(f"The harness {name} must link to the actual source checkout.")

    def git(*args):
        return subprocess.check_output(["git", "-C", str(source), *args]).decode().strip()

    def fingerprint():
        paths = sorted(set(git(
            "ls-files", "--", "lib", "packages/crisp_storage/lib",
            "packages/crisp_storage/hook", "packages/crisp_storage/pubspec.yaml",
            "packages/filen_client/lib", "packages/filen_client/pubspec.yaml",
        ).splitlines()) | {
            "pubspec.yaml", "tool/terminal_shell_setup_smoke.py",
            *["test/" + name for name in TESTS],
        })
        hashes = {path: digest((source / path).read_bytes()) for path in paths}
        return {"files": len(hashes), "aggregate_sha256": digest(encoded(hashes)), "sha256_by_path": hashes}

    def harness_inputs():
        return {
            name: {"sha256": digest((harness / name).read_bytes()), "text": (harness / name).read_text()}
            for name in ("pubspec.yaml", "pubspec.lock", ".dart_tool/package_config.json")
        }

    output.mkdir(parents=True, exist_ok=True)
    before = fingerprint()
    (output / "source-before.json").write_bytes(encoded(before))
    receipt = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": git("rev-parse", "HEAD"),
        "source_tree": git("rev-parse", "HEAD^{tree}"),
        "source_status_at_start": git("status", "--porcelain"),
        "source_before": {k: v for k, v in before.items() if k != "sha256_by_path"},
        "source_scope": "All tracked host lib files, crisp_storage lib/hook/manifest, filen_client lib/manifest, the nine selected tests, production pubspec, and the shell smoke runner.",
        "harness": str(harness), "harness_inputs": harness_inputs(),
        "runtime": json.loads((sdk / "bin/cache/flutter.version.json").read_text()),
        "runtime_artifact_sha256": {
            name: digest((sdk / name).read_bytes()) for name in (
                "bin/cache/dart-sdk/bin/dart", "bin/cache/flutter_tools.snapshot",
                "bin/cache/artifacts/engine/linux-x64/flutter_tester",
            )
        },
        "environment": {k: os.environ.get(k) for k in ("FLUTTER_ROOT", "PUB_CACHE", "TMPDIR", "CI")},
        "runner_sha256": digest(Path(__file__).read_bytes()),
        "commands": [], "uses_github_actions": False,
        "private_connections_or_credentials": False,
        "native_application_build": False,
    }
    commands = [
        ("terminal-tests", harness, [str(dart), str(flutter), "test", "--no-pub", "--concurrency=1", "--reporter", "expanded", *["test/" + name for name in TESTS]]),
        ("terminal-shell-smoke", source, [sys.executable, "tool/terminal_shell_setup_smoke.py"]),
    ]

    def save_receipt():
        (output / "receipt.json").write_bytes(encoded(receipt))

    save_receipt()
    try:
        for name, cwd, command in commands:
            started = time.monotonic()
            path = output / (name + ".log")
            with path.open("wb") as stream:
                result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
            log = path.read_text(errors="replace")
            entry = {
                "name": name, "cwd": str(cwd), "command": command,
                "exit_code": result.returncode, "seconds": round(time.monotonic() - started, 3),
                "log": path.name, "log_sha256": digest(path.read_bytes()),
            }
            if name == "terminal-tests":
                counts = re.findall(r"\+(\d+)(?: -\d+)?: All tests passed!", log)
                entry["passed_tests"] = int(counts[-1]) if counts else 0
                entry["completion_summary_found"] = bool(counts)
            else:
                counts = re.findall(r"RESULT: (\d+) passed scenarios; (\d+) failures; (\d+) skipped shells", log)
                entry["completion_summary_found"] = bool(counts)
                if counts:
                    entry.update(zip(("passed_scenarios", "failed_scenarios", "skipped_shells"), map(int, counts[-1])))
            receipt["commands"].append(entry)
            print(json.dumps(entry), flush=True)
            save_receipt()
    except (OSError, KeyboardInterrupt) as error:
        receipt["execution_error"] = str(error) or type(error).__name__
    finally:
        after = fingerprint()
        (output / "source-after.json").write_bytes(encoded(after))
        receipt["source_after"] = {k: v for k, v in after.items() if k != "sha256_by_path"}
        receipt["source_commit_after"] = git("rev-parse", "HEAD")
        receipt["source_tree_after"] = git("rev-parse", "HEAD^{tree}")
        receipt["source_unchanged"] = before == after
        receipt["head_unchanged"] = receipt["source_commit"] == receipt["source_commit_after"]
        receipt["harness_inputs_unchanged"] = receipt["harness_inputs"] == harness_inputs()
        receipt["all_commands_passed"] = len(receipt["commands"]) == len(commands) and all(
            entry["exit_code"] == 0 and entry["completion_summary_found"] for entry in receipt["commands"]
        )
        receipt["qualified"] = all(receipt[k] for k in (
            "source_unchanged", "head_unchanged", "harness_inputs_unchanged", "all_commands_passed",
        )) and "execution_error" not in receipt
        receipt["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        save_receipt()
    print(json.dumps({k: receipt[k] for k in (
        "qualified", "all_commands_passed", "source_unchanged", "head_unchanged", "harness_inputs_unchanged",
    )}), flush=True)
    return 0 if receipt["qualified"] else 1


if __name__ == "__main__":
    sys.exit(main())
