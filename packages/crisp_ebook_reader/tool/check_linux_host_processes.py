"""Assert native smoke tests leave no new WebKit/canary processes behind.

Only process IDs and kernel process names are read; no command arguments,
environment, memory, credentials or publication content are collected.
"""
from pathlib import Path
import argparse
import json
import time

parser = argparse.ArgumentParser()
parser.add_argument("mode", choices=["before", "after"])
parser.add_argument("snapshot", type=Path)
args = parser.parse_args()


def processes():
    found = set()
    for directory in Path("/proc").iterdir():
        if not directory.name.isdecimal():
            continue
        try:
            name = (directory / "comm").read_text().strip()
            if name.startswith(("WebKit", "bwrap", "xdg-dbus-proxy", "crisp_ebook_rea")):
                found.add(int(directory.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


if args.mode == "before":
    args.snapshot.write_text(json.dumps(sorted(processes())) + "\n")
else:
    original = set(json.loads(args.snapshot.read_text()))
    deadline = time.monotonic() + 3
    while True:
        remaining = processes() - original
        if not remaining:
            print("native process cleanup: no new canary/WebKit/proxy processes remain")
            break
        if time.monotonic() >= deadline:
            raise SystemExit(f"Native process cleanup left {len(remaining)} processes: {sorted(remaining)}")
        time.sleep(0.1)
