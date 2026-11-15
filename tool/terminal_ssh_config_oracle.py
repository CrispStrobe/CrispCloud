#!/usr/bin/env python3
"""Compare 14 authored SSH-config fixtures with the production Dart importer.

Requires Python 3.8+, the repository's pinned Dart SDK, and OpenSSH. Run from
any directory; relative --output paths resolve from the repository root:

    python3 tool/terminal_ssh_config_oracle.py --dart /path/to/dart

Only fixed fixtures below are accepted. ssh -G prints effective configuration;
it does not connect or run ProxyCommand. No fixture contains Match, Include,
LocalCommand, hostname canonicalization, or other configuration execution.
Temporary configuration files are removed on success and failure. No key file
is read. Exit status is 0 only if every comparison passes; failures return 1.
"""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
HELPER = "tool/terminal_ssh_config_oracle.dart"
RUNNER = "tool/terminal_ssh_config_oracle.py"
SOURCE_FILES = (
    "lib/models/ssh_config_import.dart",
    "lib/models/ssh_terminal_config.dart",
    "lib/models/ssh_jump_host.dart",
    "lib/models/ssh_terminal_authentication.dart",
    "lib/models/tmux_session_options.dart",
    "lib/models/screen_session_options.dart",
)
FIXTURES = (
    ("defaults", "Host one\nUser alice\nHost *\nPort 2200", "one", False),
    (
        "first-wins",
        "Host one\nUser alice\nPort 2200\nHost one\nUser ignored\nPort 2222",
        "one",
        False,
    ),
    (
        "global-first",
        "User first\nPort 2022\nHost one\nUser ignored\nPort 2222",
        "one",
        False,
    ),
    (
        "case-upper",
        "Host One one\nHostName %h.example\nHost One\nUser upper\nHost one\nUser lower",
        "One",
        False,
    ),
    (
        "case-lower",
        "Host One one\nHostName %h.example\nHost One\nUser upper\nHost one\nUser lower",
        "one",
        False,
    ),
    (
        "glob-include",
        "Host !dev2 dev?\nPort 2200\nHost dev1 dev2\nUser alice\nHost *\nPort 22",
        "dev1",
        False,
    ),
    (
        "glob-exclude",
        "Host !dev2 dev?\nPort 2200\nHost dev1 dev2\nUser alice\nHost *\nPort 22",
        "dev2",
        False,
    ),
    (
        "negative-only",
        "Host !other\nUser wrong\nHost one\nUser correct",
        "one",
        False,
    ),
    (
        "quoted",
        'Host = one\r\n HostName = "host.example" # comment\r\n'
        ' User = "alice"\r\n IdentityFile "~/.ssh/a # b"',
        "one",
        False,
    ),
    (
        "identity-additive",
        "Host one\nUser alice\nIdentityFile ~/.ssh/one\n"
        "Host *\nIdentityFile ~/.ssh/default",
        "one",
        False,
    ),
    (
        "no-recursive-hostname",
        "Host one\nHostName two\nUser first\nHost two\nHostName other\nUser second",
        "one",
        False,
    ),
    (
        "proxyjump-disabled-case",
        "Host box\nUser alice\nProxyJump NONE",
        "box",
        False,
    ),
    (
        "proxycommand-disabled-case",
        "Host box\nUser alice\nProxyCommand NONE",
        "box",
        False,
    ),
    (
        "proxyjump-none-command-fallback",
        "Host box\nUser alice\nProxyJump none\nProxyCommand special",
        "box",
        True,
    ),
)


def run(argv, text=None, timeout=30):
    result = subprocess.run(
        argv,
        cwd=str(ROOT),
        input=text,
        stdin=subprocess.DEVNULL if text is None else None,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=timeout,
        check=True,
    )
    return result


def version(argv):
    result = run(argv)
    return (result.stdout + result.stderr).strip()


def sha256(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def verify_fixture(source):
    # Keep the native oracle restricted even if someone later extends FIXTURES.
    allowed = {
        "host", "hostname", "user", "port", "identityfile",
        "proxyjump", "proxycommand",
    }
    for line in source.splitlines():
        match = re.match(r"^\s*([A-Za-z]+)\s*(?:=\s*)?(.*)$", line)
        if not match or match.group(1).lower() not in allowed:
            raise ValueError("fixture contains an unreviewed directive")
        keyword, value = match.group(1).lower(), match.group(2).strip()
        if keyword == "proxyjump" and value.lower() != "none":
            raise ValueError("native oracle fixtures cannot enable a jump route")
        if keyword == "proxycommand" and value.lower() not in ("none", "special"):
            raise ValueError("unreviewed ProxyCommand fixture")


def compare(name, source, alias, blocked, actual, fields):
    expected = {
        "host": fields["hostname"][0].lower(),
        "user": fields["user"][0],
        "port": int(fields["port"][0]),
    }
    found = {
        "host": actual["host"].lower() if actual["host"] else None,
        "user": actual["user"],
        "port": actual["port"],
    }
    has_identity = any(
        re.match(r"^\s*IdentityFile(?:\s|=)", line, re.IGNORECASE)
        for line in source.splitlines()
    )
    expected_hints = fields.get("identityfile", []) if has_identity else []
    failures = []
    if actual["alias"] != alias:
        failures.append("importer selected the wrong alias")
    if blocked:
        if fields.get("proxycommand") != ["special"]:
            failures.append("native disabled-ProxyJump fallback changed")
        if actual["host"] is not None or "proxycommand" not in actual["errors"]:
            failures.append("importer failed to block the effective ProxyCommand")
    else:
        if found != expected:
            failures.append("resolved destination differs")
        if actual["errors"]:
            failures.append("supported fixture unexpectedly blocked")
    if actual["identity"] != expected_hints:
        failures.append("additive identity hints differ")
    if fields.get("proxyjump"):
        failures.append("native oracle unexpectedly enables ProxyJump")
    return {
        "case": name,
        "status": "failed" if failures else "passed",
        "source": source,
        "alias": alias,
        "native_destination": expected,
        "importer_destination": found,
        "importer_blocked": actual["host"] is None,
        "expected_blocked": blocked,
        "identity_hints_checked": len(actual["identity"]),
        "native_identity_hints": expected_hints,
        "importer_identity_hints": actual["identity"],
        "importer_errors": actual["errors"],
        "failures": failures,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dart", default="dart", help="Dart executable or wrapper (default: dart)"
    )
    parser.add_argument("--ssh", default="ssh", help="OpenSSH executable (default: ssh)")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("build/terminal-ssh-config-oracle.json"),
        help="JSON receipt; relative paths resolve from repository root",
    )
    args = parser.parse_args()
    for _, source, _, _ in FIXTURES:
        verify_fixture(source)
    inputs = [
        {"source": source, "alias": alias, "defaultUsername": "fallback"}
        for _, source, alias, _ in FIXTURES
    ]
    # The helper and its model imports use only the Dart standard library.
    # Bypass DartDev so this comparison cannot initiate package resolution.
    command = [args.dart, "--disable-dart-dev", HELPER]
    actual = json.loads(run(command, json.dumps(inputs), timeout=120).stdout)
    if not isinstance(actual, list) or len(actual) != len(FIXTURES):
        raise ValueError("Dart helper did not return all fixture results")
    checks = []
    with tempfile.TemporaryDirectory(prefix="crispcloud-ssh-config-oracle-") as temporary:
        for (name, source, alias, blocked), result in zip(FIXTURES, actual):
            config = Path(temporary) / (name + ".conf")
            with config.open("w", encoding="utf-8", newline="") as stream:
                stream.write(source + "\n")
            # -F isolates these authored fixtures from user/system configuration.
            oracle = run([args.ssh, "-G", "-F", str(config), alias])
            fields = {}
            for line in oracle.stdout.splitlines():
                key, _, value = line.partition(" ")
                fields.setdefault(key, []).append(value)
            checks.append(compare(name, source, alias, blocked, result, fields))
    passed = sum(check["status"] == "passed" for check in checks)
    receipt = {
        "checked_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "status": "passed" if passed == len(checks) else "failed",
        "command": [sys.executable] + sys.argv,
        "working_directory": "repository root",
        "helper_command": command,
        "oracle_command_template": [args.ssh, "-G", "-F", "<temporary authored fixture>", "<alias>"],
        "tool_versions": {
            "python": platform.python_version(),
            "dart": version([args.dart, "--version"]),
            "openssh": version([args.ssh, "-V"]),
        },
        "tool_sha256": {path: sha256(path) for path in (RUNNER, HELPER)},
        "source_sha256": {path: sha256(path) for path in SOURCE_FILES},
        "importer_sha256": sha256("lib/models/ssh_config_import.dart"),
        "scope": (
            "Production pure Dart importer compared against local ssh -G using only "
            "14 authored fixtures. No network connections, configuration commands, "
            "includes, Match evaluation, or identity-file reads. Hostnames compared "
            "case-insensitively after case-sensitive alias evaluation. Covers the "
            "listed destination, pattern, identity-hint and disabled-proxy cases, "
            "not all OpenSSH features or live jump connections."
        ),
        "passed": passed,
        "total": len(checks),
        "checks": checks,
    }
    output = ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    for check in checks:
        if check["failures"]:
            print("FAIL {}: {}".format(check["case"], "; ".join(check["failures"])))
    print("{}: {}/{} production-importer comparisons against local ssh -G".format(
        "PASS" if passed == len(checks) else "FAIL", passed, len(checks)
    ))
    print("Receipt: {}".format(output))
    return 0 if passed == len(checks) else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr[-2000:], file=sys.stderr)
        sys.exit(1)
