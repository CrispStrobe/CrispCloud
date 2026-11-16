#!/usr/bin/env python3
"""Qualify the finite reconciled terminal cohort with actual source and locked dependencies."""

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
    "terminal_session_test.dart",
    "ssh_port_forwarding_model_test.dart",
    "ssh_port_forwarding_test.dart",
    "ssh_port_forwarding_widget_test.dart",
    "terminal_trigger_session_test.dart",
    "terminal_triggers_test.dart",
    "terminal_triggers_widget_test.dart",
]
LIVE_TESTS = ["ssh_terminal_live_test.dart", "ssh_port_forwarding_live_test.dart"]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def count_tests(log):
    tests = {}
    results = {}
    final = None
    for line in log.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "testStart":
            tests[event["test"]["id"]] = event["test"]
        elif event.get("type") == "testDone":
            results[event["testID"]] = event
        elif event.get("type") == "done":
            final = event
    visible = [event for event in results.values() if not event.get("hidden", False)]
    skipped = [event for event in visible if event.get("skipped", False)]
    passed = [event for event in visible if not event.get("skipped", False) and event.get("result") == "success"]
    failed = [event for event in visible if not event.get("skipped", False) and event.get("result") != "success"]
    return {
        "passed_tests": len(passed), "skipped_tests": len(skipped), "failed_tests": len(failed),
        "skipped_test_names": [tests.get(event["testID"], {}).get("name") for event in skipped],
        "failed_test_names": [tests.get(event["testID"], {}).get("name") for event in failed],
        "hidden_loader_events": len(results) - len(visible),
        "completion_summary_found": final is not None,
        "test_protocol_success": final is not None and final.get("success") is True,
        "passed_test_names": [tests.get(event["testID"], {}).get("name") for event in passed],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--harness", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--with-loopback", action="store_true")
    args = parser.parse_args()
    source = args.source.resolve()
    harness = (args.harness or source.parent / "zotero-toolchain/crisp-terminal-harness").resolve()
    output = args.output.resolve()
    sdk = Path(os.environ["FLUTTER_ROOT"]).resolve()
    dart = sdk / "bin/cache/dart-sdk/bin/dart"
    flutter = sdk / "bin/cache/flutter_tools.snapshot"
    for name in ("lib", "test"):
        if (harness / name).resolve() != source / name:
            parser.error(f"The harness {name} must link to the actual source checkout.")

    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(source), *arguments]).decode().strip()

    def fingerprint():
        # Resolve the actual transitive local Dart source inputs, including
        # conditional imports and package-local libraries. The Office vendor is
        # a separate qualification scope and is intentionally not fingerprinted.
        local_packages = {
            "crisp_cloud": source / "lib",
            "crisp_storage": source / "packages/crisp_storage/lib",
            "filen_client": source / "packages/filen_client/lib",
        }
        pending = [source / "test" / name for name in TESTS + LIVE_TESTS]
        paths = set()
        while pending:
            path = pending.pop().resolve()
            if path in paths or not path.is_file() or not path.is_relative_to(source):
                continue
            paths.add(path)
            for directive in re.findall(r"\b(?:import|export|part)\s+([^;]*);", path.read_text()):
                for uri in re.findall(r"['\"]([^'\"]+)['\"]", directive):
                    if uri.startswith("package:"):
                        package, _, suffix = uri[8:].partition("/")
                        if package in local_packages:
                            pending.append(local_packages[package] / suffix)
                    elif ":" not in uri:
                        pending.append(path.parent / uri)
        for relative in (
            "pubspec.yaml", "analysis_options.yaml", "packages/crisp_storage/pubspec.yaml",
            "packages/filen_client/pubspec.yaml", "tool/terminal_shell_setup_smoke.py",
            "tool/run_terminal_live_smoke.py",
        ):
            paths.add(source / relative)
        paths.update((source / "packages/crisp_storage/hook").rglob("*.dart"))
        hashes = {str(path.relative_to(source)): digest(path.read_bytes()) for path in sorted(paths)}
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
        "source_before": {key: value for key, value in before.items() if key != "sha256_by_path"},
        "source_scope": "The 16 selected core tests, two optional live tests, their transitive local Dart imports (including conditional imports), production/harness manifests and lock, storage hook, and two smoke runners. Office vendor qualification is separate.",
        "harness": str(harness), "harness_inputs": harness_inputs(),
        "runtime": json.loads((sdk / "bin/cache/flutter.version.json").read_text()),
        "runtime_artifact_sha256": {
            name: digest((sdk / name).read_bytes()) for name in (
                "bin/cache/dart-sdk/bin/dart", "bin/cache/flutter_tools.snapshot",
                "bin/cache/artifacts/engine/linux-x64/flutter_tester",
            )
        },
        "environment": {key: os.environ.get(key) for key in ("FLUTTER_ROOT", "PUB_CACHE", "TMPDIR", "CI")},
        "runner_sha256": digest(Path(__file__).read_bytes()),
        "commands": [], "uses_github_actions": False,
        "private_connections_or_credentials": False,
        "loopback_only_with_disposable_keys": args.with_loopback,
        "native_application_build": False,
    }
    commands = [
        ("terminal-tests", harness, [str(dart), str(flutter), "test", "--no-pub", "--concurrency=1", "--reporter=json", *["test/" + name for name in TESTS]]),
        ("terminal-shell-smoke", source, [sys.executable, "tool/terminal_shell_setup_smoke.py"]),
    ]
    if args.with_loopback:
        wrapper = harness / ".dart_tool/terminal-evidence-flutter"
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        wrapper.write_text(
            "#!/usr/bin/env python3\nimport os, sys\n"
            f"command = {[str(dart), str(flutter)]!r}\n"
            "command.extend('--reporter=json' if arg == '--reporter=expanded' else arg for arg in sys.argv[1:])\n"
            "os.execv(command[0], command)\n"
        )
        wrapper.chmod(0o755)
        commands.append(("terminal-loopback", source, [sys.executable, "tool/run_terminal_live_smoke.py", "--flutter", str(wrapper), "--project", str(harness)]))
        receipt["loopback_wrapper_sha256"] = digest(wrapper.read_bytes())
        receipt["loopback_pty_enabled"] = False

    def save_receipt():
        (output / "receipt.json").write_bytes(encoded(receipt))

    save_receipt()
    try:
        for name, cwd, command in commands:
            started = time.monotonic()
            path = output / (name + ".log")
            print(json.dumps({"starting": name, "command": command}), flush=True)
            with path.open("wb") as stream:
                result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
            log = path.read_text(errors="replace")
            entry = {
                "name": name, "cwd": str(cwd), "command": command,
                "exit_code": result.returncode, "seconds": round(time.monotonic() - started, 3),
                "log": path.name, "log_sha256": digest(path.read_bytes()),
            }
            if name in ("terminal-tests", "terminal-loopback"):
                entry.update(count_tests(log))
                entry["passed"] = result.returncode == 0 and entry["test_protocol_success"] and entry["failed_tests"] == 0 and entry["passed_tests"] > 0
                if name == "terminal-tests":
                    entry["passed"] = entry["passed"] and entry["skipped_tests"] == 0
                else:
                    # The fixture deliberately does not request privileged PTY
                    # accounting. The existing optional PTY test stays visible.
                    entry["passed"] = entry["passed"] and entry["skipped_test_names"] == [
                        "real OpenSSH loopback route real PTY receives size changes and preserves final output and exit status"
                    ]
            else:
                counts = re.findall(r"RESULT: (\d+) passed scenarios; (\d+) failures; (\d+) skipped shells", log)
                entry["completion_summary_found"] = bool(counts)
                if counts:
                    entry.update(zip(("passed_scenarios", "failed_scenarios", "skipped_shells"), map(int, counts[-1])))
                entry["passed"] = result.returncode == 0 and bool(counts) and entry.get("failed_scenarios") == 0 and entry.get("skipped_shells") == 0
            receipt["commands"].append(entry)
            print(json.dumps({key: value for key, value in entry.items() if key != "passed_test_names"}), flush=True)
            save_receipt()
    except (OSError, KeyboardInterrupt) as error:
        receipt["execution_error"] = str(error) or type(error).__name__
    finally:
        after = fingerprint()
        (output / "source-after.json").write_bytes(encoded(after))
        receipt["source_after"] = {key: value for key, value in after.items() if key != "sha256_by_path"}
        receipt["source_commit_after"] = git("rev-parse", "HEAD")
        receipt["source_tree_after"] = git("rev-parse", "HEAD^{tree}")
        receipt["source_unchanged"] = before == after
        receipt["head_unchanged"] = receipt["source_commit"] == receipt["source_commit_after"]
        receipt["harness_inputs_unchanged"] = receipt["harness_inputs"] == harness_inputs()
        receipt["all_commands_passed"] = len(receipt["commands"]) == len(commands) and all(entry["passed"] for entry in receipt["commands"])
        # Concurrent documentation/checkpoint commits are allowed; the tested
        # input byte fingerprints, not unrelated HEAD movement, are the gate.
        receipt["qualified"] = all(receipt[key] for key in (
            "source_unchanged", "harness_inputs_unchanged", "all_commands_passed",
        )) and "execution_error" not in receipt
        receipt["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        save_receipt()
    print(json.dumps({key: receipt[key] for key in (
        "qualified", "all_commands_passed", "source_unchanged", "head_unchanged", "harness_inputs_unchanged",
    )}), flush=True)
    return 0 if receipt["qualified"] else 1


if __name__ == "__main__":
    sys.exit(main())
