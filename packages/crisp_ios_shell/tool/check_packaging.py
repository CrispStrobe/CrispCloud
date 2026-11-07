#!/usr/bin/env python3
"""Reject missing runtime frameworks or eager command linkage in a built iOS app."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys


def validate(app: Path) -> None:
    package = Path(__file__).resolve().parents[1]
    manifest = json.loads((package / "tool/sources.json").read_text())
    frameworks = app / "Frameworks"
    for name in manifest["targets"] + manifest["dash_variants"]:
        if not (frameworks / f"{name}.framework" / name).is_file():
            raise RuntimeError(f"App is missing required {name}.framework")
    command_names = manifest["targets"][1:] + manifest["dash_variants"]
    executable = plistlib.loads((app / "Info.plist").read_bytes())["CFBundleExecutable"]
    inspected = [app / executable]
    plugin = frameworks / "crisp_ios_shell.framework/crisp_ios_shell"
    if plugin.exists():
        inspected.append(plugin)
    has_runtime = False
    for binary in inspected:
        dependencies = subprocess.check_output(["xcrun", "otool", "-L", str(binary)], text=True)
        has_runtime |= "ios_system.framework/ios_system" in dependencies
        for name in command_names:
            if f"/{name}.framework/{name}" in dependencies:
                raise RuntimeError(f"{binary.name} eagerly links {name}; preserve -dead_strip_dylibs so command globals can reset")
    if not has_runtime:
        raise RuntimeError("App/plugin does not link the real ios_system runtime")
    print("Verified embedded runtime and on-demand command loading.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_packaging.py path/to/App.app")
    validate(Path(sys.argv[1]).resolve())
