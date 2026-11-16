#!/usr/bin/env python3
"""Qualify current terminal/agent/profile inputs with actual source and locked dependencies.

Extends the preceding continuation runner; every selected test executes once
per phase. Core, live and shell counts remain separate, with source and lock
identity required throughout. This runner never contacts GitHub Actions.
"""

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
from urllib.parse import unquote, urljoin, urlparse


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
    "ssh_agent_channel_test.dart",
    "ssh_agent_profiles_test.dart",
    "ssh_agent_route_test.dart",
    "ssh_agent_test.dart",
    "ssh_public_key_auth_test.dart",
    "ssh_forwarding_profiles_test.dart",
    "ssh_forwarding_profiles_widget_test.dart",
    "ssh_terminal_profiles_test.dart",
    "ssh_native_tmux_persistence_test.dart",
    "terminal_input_budget_test.dart",
    "tmux_control_client_test.dart",
    "tmux_control_protocol_test.dart",
    "tmux_session_options_test.dart",
]
LIVE_TESTS = [
    "ssh_terminal_live_test.dart", "ssh_port_forwarding_live_test.dart",
    "ssh_agent_live_test.dart",
]
PTY_SKIP = "real OpenSSH loopback route real PTY receives size changes and preserves final output and exit status"
UNIX_AGENT_SKIP = "actual disposable Unix ssh-agent authenticates and forwards to ssh-add"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def count_tests(log):
    tests = {}
    suites = {}
    results = {}
    final = None
    for line in log.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "suite":
            suites[event["suite"]["id"]] = event["suite"]
        elif event.get("type") == "testStart":
            tests[event["test"]["id"]] = event["test"]
        elif event.get("type") == "testDone":
            results[event["testID"]] = event
        elif event.get("type") == "done":
            final = event
    visible = [event for event in results.values() if not event.get("hidden", False)]
    skipped = [event for event in visible if event.get("skipped", False)]
    passed = [event for event in visible if not event.get("skipped", False) and event.get("result") == "success"]
    failed = [event for event in visible if not event.get("skipped", False) and event.get("result") != "success"]
    per_suite = {}
    identities = []
    for event in visible:
        test = tests.get(event["testID"], {})
        suite = suites.get(test.get("suiteID"), {})
        path = suite.get("path", "unknown")
        name = Path(path).name
        counts = per_suite.setdefault(name, {"passed": 0, "skipped": 0, "failed": 0})
        result = "skipped" if event.get("skipped", False) else "passed" if event.get("result") == "success" else "failed"
        counts[result] += 1
        identities.append((name, test.get("name")))
    return {
        "passed_tests": len(passed), "skipped_tests": len(skipped), "failed_tests": len(failed),
        "skipped_test_names": [tests.get(event["testID"], {}).get("name") for event in skipped],
        "failed_test_names": [tests.get(event["testID"], {}).get("name") for event in failed],
        "hidden_loader_events": len(results) - len(visible),
        "completion_summary_found": final is not None,
        "test_protocol_success": final is not None and final.get("success") is True,
        "passed_test_names": [tests.get(event["testID"], {}).get("name") for event in passed],
        "counts_by_file": per_suite,
        "duplicate_visible_test_identities": len(identities) - len(set(identities)),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--harness", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--with-loopback", action="store_true")
    parser.add_argument("--with-unix-agent", action="store_true", help="Request an actual disposable ssh-agent when the host permits Unix sockets.")
    parser.add_argument("--loopback-only", action="store_true", help="Repeat only the optional loopback selection after a documented environmental failure.")
    args = parser.parse_args()
    if args.loopback_only and not args.with_loopback:
        parser.error("--loopback-only requires --with-loopback")
    if args.with_unix_agent and not args.with_loopback:
        parser.error("--with-unix-agent requires --with-loopback")
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

    config_path = harness / ".dart_tool/package_config.json"

    def package_roots():
        result = {}
        for entry in json.loads(config_path.read_text())["packages"]:
            uri = urljoin(config_path.as_uri(), entry["rootUri"])
            if urlparse(uri).scheme != "file":
                raise ValueError("Resolved package root is not local: " + entry["name"])
            root = Path(unquote(urlparse(uri).path)).resolve()
            result[entry["name"]] = (root, (root / entry.get("packageUri", "lib/")).resolve())
        if result.get("dartssh2", (None,))[0] != source / "packages/dartssh2":
            raise ValueError("The harness must execute the current production vendored dartssh2.")
        return result

    def fingerprint():
        # Resolve the actual transitive local Dart source inputs, including
        # conditional imports and package-local libraries. The Office vendor is
        # a separate qualification scope and is intentionally not fingerprinted.
        local_packages = {
            name: library for name, (_, library) in package_roots().items()
            if library.is_relative_to(source)
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
            "pubspec.yaml", "pubspec.lock", ".fvmrc", "analysis_options.yaml", "packages/crisp_storage/pubspec.yaml",
            "packages/filen_client/pubspec.yaml", "tool/terminal_shell_setup_smoke.py",
            "tool/run_terminal_live_smoke.py", "tool/verify_dartssh2_vendor.py",
        ):
            paths.add(source / relative)
        paths.update((source / "packages/crisp_storage/hook").rglob("*.dart"))
        # Include all pinned upstream files, every locally patched runtime file,
        # the patch itself and both provenance inventories, not just imported code.
        paths.update(source / name for name in git("ls-files", "packages/dartssh2").splitlines())
        hashes = {str(path.relative_to(source)): digest(path.read_bytes()) for path in sorted(paths)}
        return {"files": len(hashes), "aggregate_sha256": digest(encoded(hashes)), "sha256_by_path": hashes}

    def harness_inputs():
        return {
            name: {"sha256": digest((harness / name).read_bytes()), "text": (harness / name).read_text()}
            for name in ("pubspec.yaml", "pubspec.lock", ".dart_tool/package_config.json")
        }

    output.mkdir(parents=True, exist_ok=True)
    dependency_started = time.monotonic()
    locked_inputs = {
        "harness/" + name: digest((harness / name).read_bytes())
        for name in ("pubspec.yaml", "pubspec.lock")
    }
    locked_inputs.update({
        "production/" + name: digest((source / name).read_bytes())
        for name in ("pubspec.yaml", "pubspec.lock")
    })
    dependency_command = [str(dart), str(flutter), "pub", "get", "--offline", "--enforce-lockfile"]
    dependency_log = output / "pub-get-offline-enforce.log"
    with dependency_log.open("wb") as stream:
        dependency_result = subprocess.run(dependency_command, cwd=harness, stdout=stream, stderr=subprocess.STDOUT)
    after_locks = {
        label: digest(((harness if label.startswith("harness/") else source) / label.split("/", 1)[1]).read_bytes())
        for label in locked_inputs
    }
    if dependency_result.returncode != 0 or locked_inputs != after_locks:
        parser.error("Offline enforced dependency resolution failed or changed a locked manifest; inspect " + str(dependency_log))
    roots = package_roots()
    lock = (harness / "pubspec.lock").read_text()
    packages = {}
    for name, block in re.findall(r"^  ([a-zA-Z0-9_]+):\n((?: {4,}[^\n]*\n)+)", lock, re.M):
        source_kind = re.search(r"^    source: (\S+)", block, re.M).group(1)
        version = re.search(r'^    version: "?([^"\n]+)"?$', block, re.M).group(1)
        item = {"source": source_kind, "version": version, "resolved_root": str(roots[name][0])}
        if source_kind == "hosted":
            expected = re.search(r'^      sha256: "?([a-f0-9]{64})"?$', block, re.M).group(1)
            marker = Path(os.environ["PUB_CACHE"]) / "hosted-hashes/pub.dev" / (name + "-" + version + ".sha256")
            observed = marker.read_text().strip() if marker.is_file() else None
            item.update(locked_archive_sha256=expected, cached_archive_sha256=observed,
                        archive_hash_matches=observed == expected)
        packages[name] = item
    if not packages or len(packages) + 1 != len(roots):
        parser.error("The complete package configuration must match the saved lock plus the harness root.")
    dependencies = {
        "command": dependency_command, "cwd": str(harness), "exit_code": dependency_result.returncode,
        "seconds": round(time.monotonic() - dependency_started, 3),
        "log": dependency_log.name, "log_sha256": digest(dependency_log.read_bytes()),
        "locked_inputs": locked_inputs, "manifests_and_locks_unchanged": locked_inputs == after_locks,
        "locked_package_count": len(packages), "resolved_package_count_including_root": len(roots),
        "source_counts": {kind: sum(item["source"] == kind for item in packages.values()) for kind in ("hosted", "path", "sdk")},
        "all_hosted_archive_hashes_match": all(item.get("archive_hash_matches", True) for item in packages.values()),
        "packages": packages,
    }
    (output / "dependency-inputs.json").write_bytes(encoded(dependencies))
    if not dependencies["all_hosted_archive_hashes_match"]:
        parser.error("One or more cached hosted archive hash markers do not match the enforced lock.")
    for name in ("pubspec.yaml", "pubspec.lock"):
        (output / name).write_bytes((harness / name).read_bytes())
    setup_inputs = {}
    for name in ("terminal-setup-receipt.json", "terminal-reconstruction.json", "runtime-setup-summary.json"):
        path = harness.parent / name
        if path.is_file():
            (output / name).write_bytes(path.read_bytes())
            setup_inputs[name] = digest(path.read_bytes())
    before = fingerprint()
    (output / "source-before.json").write_bytes(encoded(before))
    receipt = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": git("rev-parse", "HEAD"),
        "source_tree": git("rev-parse", "HEAD^{tree}"),
        "source_status_at_start": git("status", "--porcelain"),
        "source_before": {key: value for key, value in before.items() if key != "sha256_by_path"},
        "source_scope": f"The {len(TESTS)} selected core tests, {len(LIVE_TESTS)} optional live tests, their transitive local Dart imports (including conditional imports), complete tracked dartssh2 vendor/provenance, production manifests and lock, storage hook, and smoke/vendor runners. Full app and Office qualification are separate.",
        "tests": TESTS, "live_tests": LIVE_TESTS,
        "dependencies": {key: value for key, value in dependencies.items() if key != "packages"},
        "prior_runtime_setup_inputs": setup_inputs,
        "incoming_terminal_commit": git("rev-parse", "6e11d2d6fda1486dc6968e01137ba7466356398f^{commit}"),
        "incoming_terminal_is_ancestor": subprocess.run(["git", "-C", str(source), "merge-base", "--is-ancestor", "6e11d2d6fda1486dc6968e01137ba7466356398f", "HEAD"]).returncode == 0,
        "focused_graph_exclusions": {
            "ssh_agent_widget_test.dart": "Full filesystem/archive/backend dependency graph; retained initial compilation failure.",
            "terminal_mount_localization_test.dart": "Full filesystem/archive/backend dependency graph; retained initial compilation failure.",
            "ssh_terminal_transport_test.dart": "Imports full terminal_backends/local filesystem graph absent from focused harness.",
            "ssh_tmux_panel_lifecycle_test.dart": "Imports full terminal panel/core providers graph absent from focused harness.",
            "tmux_control_workspace_test.dart": "Imports terminal_provider/core providers graph absent from focused harness.",
        },
        "native_tmux_binary_acceptance": "Not run: no system tmux binary installed. Protocol/client/input/persistence are exercised in the unit cohort.",
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
        "selection": "loopback-only" if args.loopback_only else "core-and-shell",
        "native_application_build": False,
    }
    commands = [("dartssh2-vendor", source, [sys.executable, "tool/verify_dartssh2_vendor.py", "--require-tracked"])]
    commands += [] if args.loopback_only else [
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
        command = [sys.executable, "tool/run_terminal_live_smoke.py", "--flutter", str(wrapper), "--project", str(harness)]
        if args.with_unix_agent:
            command.append("--with-unix-agent")
        commands.append(("terminal-loopback", source, command))
        receipt["loopback_wrapper_sha256"] = digest(wrapper.read_bytes())
        receipt["loopback_pty_enabled"] = False
        receipt["disposable_unix_agent_requested"] = args.with_unix_agent

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
                entry["passed"] = result.returncode == 0 and entry["test_protocol_success"] and entry["failed_tests"] == 0 and entry["passed_tests"] > 0 and entry["duplicate_visible_test_identities"] == 0
                if name == "terminal-tests":
                    entry["passed"] = entry["passed"] and entry["skipped_tests"] == 0 and set(entry["counts_by_file"]) == set(TESTS)
                    (output / "core-test-counts.json").write_bytes(encoded(entry["counts_by_file"]))
                else:
                    # The fixture deliberately does not request privileged PTY
                    # accounting. The existing optional PTY test stays visible.
                    allowed = {PTY_SKIP, UNIX_AGENT_SKIP}
                    entry["passed"] = entry["passed"] and PTY_SKIP in entry["skipped_test_names"] and set(entry["skipped_test_names"]) <= allowed and set(entry["counts_by_file"]) == set(LIVE_TESTS)
                    entry["actual_unix_agent_passed"] = UNIX_AGENT_SKIP in entry["passed_test_names"]
                    (output / "live-test-counts.json").write_bytes(encoded(entry["counts_by_file"]))
            elif name == "dartssh2-vendor":
                entry["passed"] = result.returncode == 0 and "Verified 96 dartssh2 4.1.0 upstream files; 4 reviewed agent-channel patches." in log
            else:
                counts = re.findall(r"RESULT: (\d+) passed scenarios; (\d+) failures; (\d+) skipped shells", log)
                entry["completion_summary_found"] = bool(counts)
                if counts:
                    entry.update(zip(("passed_scenarios", "failed_scenarios", "skipped_shells"), map(int, counts[-1])))
                entry["passed"] = result.returncode == 0 and bool(counts) and entry.get("failed_scenarios") == 0 and entry.get("skipped_shells") == 0
            receipt["commands"].append(entry)
            print(json.dumps({key: value for key, value in entry.items() if key not in ("passed_test_names", "counts_by_file")}), flush=True)
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
            "source_unchanged", "harness_inputs_unchanged", "all_commands_passed", "incoming_terminal_is_ancestor",
        )) and "execution_error" not in receipt
        receipt["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        save_receipt()
    print(json.dumps({key: receipt[key] for key in (
        "qualified", "all_commands_passed", "source_unchanged", "head_unchanged", "harness_inputs_unchanged",
    )}), flush=True)
    return 0 if receipt["qualified"] else 1


if __name__ == "__main__":
    sys.exit(main())
