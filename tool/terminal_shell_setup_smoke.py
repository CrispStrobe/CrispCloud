#!/usr/bin/env python3
"""Exercise the actual copied shell helpers in fresh interactive Bash/Zsh.

Run from any directory: python3 tool/terminal_shell_setup_smoke.py
Older Bash: add --bash /path/to/bash-4.4 --bash /path/to/bash-5.0.
Explicit paths replace automatic discovery for that shell. No startup files are
changed. Exit codes: 0 = some coverage passed, 1 = failure, 77 = all skipped.
SKIP lines are not passing coverage. Requires a POSIX host and Python 3.8+.
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
from urllib.parse import quote_from_bytes


CASE = re.compile(rb"\x1eCC_CASE:([a-z0-9_]+)\x1f")
HOOK = re.compile(rb"\x1eCC_HOOK_([AB]):([0-9]+)\x1f")
OSC133 = re.compile(rb"\x1b\]133;([ABCD])(?:;([0-9]+))?\x07")
OSC7 = re.compile(rb"\x1b\]7;([^\x07]*)\x07")
CASES = [
    ("once_false", [0, 1]),
    ("once_exit7", [0, 7]),
    ("source_again", [0, 0]),
    ("twice_false", [0, 1]),
    ("twice_exit7", [0, 7]),
]


def extract_helpers(source):
    """Read production literals, not a second implementation of the hooks."""
    data = source.read_bytes()
    matches = re.findall(
        r"(?ms)^const _(bash|zsh)\s*=\s*r'''(.*?)''';[ \t]*$",
        data.decode("utf-8"),
    )
    helpers = dict(matches)
    if len(matches) != 2 or set(helpers) != {"bash", "zsh"}:
        raise RuntimeError("expected exactly one raw _bash and _zsh Dart literal")
    print("SOURCE {} sha256={}".format(source, hashlib.sha256(data).hexdigest()))
    return helpers


def run_process(argv, directory, environment, text, timeout):
    process = subprocess.Popen(
        argv,
        cwd=str(directory),
        env=environment,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(text.encode("utf-8"), timeout=timeout)
        return process.returncode, output
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            output, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            if process.stdout:
                process.stdout.close()
            output = b"(output pipe did not close after process-group shutdown)"
        raise RuntimeError(
            "exceeded {}s; output tail={!r}".format(timeout, output[-2000:])
        ) from None


def shell_program(kind, mode, helper):
    # A/B are existing downstream prompt hooks. Bash must return the saved
    # status to preserve scalar sequencing; Zsh supplies each hook's status.
    hook_return = '"$__cc_smoke_saved"' if kind == "bash" else "0"
    lines = ["PS1='CC_SMOKE_PROMPT> '; PS0=''; PS2=''"]
    for label in ("A", "B"):
        lines.append(
            "__cc_smoke_hook_{label}() {{ "
            "local __cc_smoke_saved=$?; "
            "builtin printf '\\036CC_HOOK_{label}:%d\\037\\n' "
            '"$__cc_smoke_saved"; return {result}; }}'.format(
                label=label, result=hook_return
            )
        )
    if kind == "bash":
        if mode == "array":
            lines.append("PROMPT_COMMAND=(__cc_smoke_hook_A __cc_smoke_hook_B)")
        else:
            lines.append("PROMPT_COMMAND='__cc_smoke_hook_A; __cc_smoke_hook_B'")
    else:
        lines.append("precmd_functions=(__cc_smoke_hook_A __cc_smoke_hook_B)")
    source = ". {}".format(shlex.quote(str(helper)))
    lines.append(source)
    commands = ["false", "(exit 7)", source, "false", "(exit 7)"]
    for (name, _), command in zip(CASES, commands):
        lines.append("builtin printf '\\036CC_CASE:%s\\037\\n' '{}'".format(name))
        lines.append(command)
    lines.append("builtin printf '\\036CC_CASE:%s\\037\\n' 'finished'")
    lines.append("exit 0")
    return "\n".join(lines) + "\n"


def verify_output(output, directory):
    markers = list(CASE.finditer(output))
    expected_names = [name for name, _ in CASES] + ["finished"]
    names = [match[1].decode("ascii") for match in markers]
    if names != expected_names:
        raise RuntimeError("incomplete or duplicate case markers: {!r}".format(names))
    expected_uri = (
        "file://" + quote_from_bytes(os.fsencode(str(directory)), safe="/._~-")
    ).encode("ascii")
    for index, (name, expected_statuses) in enumerate(CASES):
        segment = output[markers[index].end():markers[index + 1].start()]
        events = OSC133.findall(segment)
        statuses = [int(status) for event, status in events if event == b"D"]
        # Each segment contains a successful case-marker command and then
        # the tested command. The next command's C precedes its case marker.
        if statuses != expected_statuses:
            raise RuntimeError("{}: exit statuses {!r}, expected {!r}".format(
                name, statuses, expected_statuses
            ))
        for event in (b"A", b"B", b"C", b"D"):
            count = sum(found == event for found, _ in events)
            if count != 2:
                raise RuntimeError("{}: {} marker count {}, expected 2".format(
                    name, event.decode("ascii"), count
                ))
        expected_hooks = [
            (label, str(status).encode("ascii"))
            for status in expected_statuses for label in (b"A", b"B")
        ]
        if HOOK.findall(segment) != expected_hooks:
            raise RuntimeError("{}: downstream prompt hook order/status changed: {!r}".format(
                name, HOOK.findall(segment)
            ))
        if OSC7.findall(segment) != [expected_uri, expected_uri]:
            raise RuntimeError("{}: OSC7 did not encode the exact Unicode cwd: {!r}".format(
                name, OSC7.findall(segment)
            ))
        if segment.count(b"CC_SMOKE_PROMPT> ") != 2:
            raise RuntimeError("{}: original prompt was lost or duplicated".format(name))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bash", action="append", metavar="PATH")
    parser.add_argument("--zsh", action="append", metavar="PATH")
    parser.add_argument(
        "--source", type=Path,
        default=Path(__file__).resolve().parents[1] / "lib/services/terminal_shell_setup.dart",
    )
    parser.add_argument("--timeout", type=float, default=12, metavar="SECONDS")
    args = parser.parse_args()
    if not 1 <= args.timeout <= 60:
        parser.error("--timeout must be between 1 and 60 seconds")
    if os.name != "posix":
        print("SKIP: this harness requires POSIX interactive shells")
        return 77
    try:
        helpers = extract_helpers(args.source.resolve())
    except (OSError, UnicodeError, RuntimeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        return 1

    passed = failed = skipped = 0
    with tempfile.TemporaryDirectory(prefix="crispcloud-shell-smoke-") as temporary:
        root = Path(temporary).resolve()
        directory = root / "space # percent% café 日本"
        directory.mkdir()
        environment = os.environ.copy()
        for key in list(environment):
            if key.startswith("BASH_FUNC_") or key in {
                "BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "PROMPT_COMMAND",
                "PS0", "PS1", "PS2", "PROMPT", "RPROMPT",
                "__crispcloud_shell_integration",
            }:
                environment.pop(key, None)
        environment.update({
            "TERM": "dumb", "LC_ALL": "C", "LANG": "C",
            "PWD": str(directory), "ZDOTDIR": str(root),
        })
        for kind in ("bash", "zsh"):
            candidates = getattr(args, kind) or [kind]
            for requested in candidates:
                executable = shutil.which(os.path.expanduser(requested))
                if executable is None:
                    print("SKIP {}: executable not found".format(requested))
                    skipped += 1
                    continue
                try:
                    code, version_text = run_process(
                        [executable, "--version"], root, environment, "", 5
                    )
                    pattern = (
                        rb"\bversion\s+([0-9]+)\.([0-9]+)"
                        if kind == "bash" else rb"\bzsh\s+([0-9]+)\.([0-9]+)"
                    )
                    match = re.search(pattern, version_text)
                    if code or match is None:
                        raise RuntimeError("cannot identify {}: {!r}".format(
                            kind, version_text[:500]
                        ))
                    version = (int(match[1]), int(match[2]))
                    minimum = (4, 4) if kind == "bash" else (5, 0)
                    if version < minimum:
                        print("SKIP {} {}.{}: runner requires {}.{}+".format(
                            executable, *version, *minimum
                        ))
                        skipped += 1
                        continue
                except (OSError, RuntimeError) as error:
                    print("FAIL {}: {}".format(executable, error))
                    failed += 1
                    continue

                helper = root / ("actual-helper." + kind)
                helper.write_text(helpers[kind], encoding="utf-8")
                modes = ["scalar", "array"] if kind == "bash" and version >= (5, 1) else ["scalar"]
                if kind == "zsh":
                    modes = ["precmd"]
                flags = ["--noprofile", "--norc", "--noediting", "-i"] if kind == "bash" else ["-f", "-i"]
                for mode in modes:
                    label = "{} {}.{} {}".format(executable, *version, mode)
                    output = b""
                    try:
                        code, output = run_process(
                            [executable] + flags, directory, environment,
                            shell_program(kind, mode, helper), args.timeout,
                        )
                        if code:
                            raise RuntimeError("interactive shell exited {}".format(code))
                        verify_output(output, directory)
                    except (OSError, RuntimeError) as error:
                        print("FAIL {}: {}".format(label, error))
                        if output:
                            print("  output tail={!r}".format(output[-3000:]))
                        failed += 1
                    else:
                        print("PASS {}: exit1/7, hook status/order, Unicode cwd, idempotence".format(label))
                        passed += 1

    print("RESULT: {} passed scenarios; {} failures; {} skipped shells".format(
        passed, failed, skipped
    ))
    return 1 if failed else (0 if passed else 77)


if __name__ == "__main__":
    sys.exit(main())
