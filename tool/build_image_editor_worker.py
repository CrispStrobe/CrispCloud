"""Build the shipped image worker using CrispCloud's locked dependencies."""

import argparse
import hashlib
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--emit-review", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    package = root / "packages/pro_image_editor"
    names = ("web_worker.dart.js", "web_worker.dart.js.map")
    paths = [package / "lib/web" / name for name in names]
    before = [path.read_bytes() for path in paths]
    if not (root / ".dart_tool/package_config.json").is_file():
        parser.error("Run flutter pub get in the repository root first.")
    subprocess.run(
        [
            "dart", "compile", "js",
            "--packages=../../.dart_tool/package_config.json",
            "-o", "lib/web/web_worker.dart.js", "lib/web/web_worker.dart",
        ],
        cwd=package,
        check=True,
    )
    after = [path.read_bytes() for path in paths]
    for name, data in zip(names, after):
        print(f"{hashlib.sha256(data).hexdigest()}  {name}")
    changed = before != after
    if args.emit_review:
        destination = root / "build/image_editor_worker"
        destination.mkdir(parents=True, exist_ok=True)
        for name, data in zip(names, after):
            (destination / name).write_bytes(data)
        print("Saved the compiled worker and source map for review.")
    if args.check and changed:
        print("The committed image worker differs from its pinned build.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
