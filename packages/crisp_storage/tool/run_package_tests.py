#!/usr/bin/env python3
"""Run package tests with a bounded macOS native-asset install path."""

from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile


PACKAGE_ROOT = Path(__file__).resolve().parent.parent
EXCLUDED = {
    ".dart_tool", ".git", ".cache", ".pytest_cache", ".mypy_cache",
    ".ruff_cache", "__pycache__", "build", "target", ".venv", "venv",
    ".fixture-venv", ".smb-venv", ".tox", ".nox",
}


def ignore_generated(directory, names):
    ignored = []
    for name in names:
        entry = Path(directory) / name
        if (name in EXCLUDED or name.endswith((".pyc", ".pyo"))
                or (entry.is_dir() and (entry / "pyvenv.cfg").is_file())):
            ignored.append(name)
    return ignored


def status(returncode):
    return returncode if returncode >= 0 else 128 - returncode


def run_tests(arguments):
    command = ["dart", "test", *arguments]
    if sys.platform != "darwin":
        return status(subprocess.run(command, cwd=PACKAGE_ROOT, check=False).returncode)

    lock = PACKAGE_ROOT / "pubspec.lock"
    if not lock.is_file():
        print("Run dart pub get in packages/crisp_storage before this wrapper.",
              file=sys.stderr)
        return 2
    resolved_lock = lock.read_bytes()

    # The pinned libsmb2 arm64 image cannot accommodate the long Actions path.
    # Use a physical copy: a symlink can resolve back to that original path.
    with tempfile.TemporaryDirectory(prefix="cc-smb-", dir="/private/tmp") as temporary:
        destination = Path(temporary).resolve(strict=True)
        install_name = destination / ".dart_tool" / "lib" / "libdart_smb2"
        # The pinned image permits an 87-byte ID; retain a margin below that.
        if len(str(install_name).encode("utf-8")) > 80:
            print("The temporary SMB native-asset install path is too long.",
                  file=sys.stderr)
            return 1
        shutil.copytree(PACKAGE_ROOT, destination, dirs_exist_ok=True,
                        symlinks=True, ignore=ignore_generated)
        destination.chmod(0o700)
        copied_lock = destination / "pubspec.lock"
        if copied_lock.read_bytes() != resolved_lock:
            print("The package lockfile changed while preparing the test copy.",
                  file=sys.stderr)
            return 1

        result = subprocess.run(
            ["dart", "pub", "get", "--offline", "--enforce-lockfile"],
            cwd=destination, check=False,
        )
        if result.returncode != 0:
            return status(result.returncode)
        if copied_lock.read_bytes() != resolved_lock:
            print("Dependency resolution changed the copied lockfile.", file=sys.stderr)
            return 1
        return status(subprocess.run(command, cwd=destination, check=False).returncode)


def terminate(signum, _frame):
    # Unwind TemporaryDirectory and subprocess.run on workflow cancellation.
    raise SystemExit(128 + signum)


def main(arguments):
    if arguments in (["--help"], ["-h"]):
        print("Usage: python3 tool/run_package_tests.py [--] [dart test arguments]")
        print(__doc__)
        print("Other hosts run dart test directly. Use -- --help for Dart test help.")
        return 0
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    signal.signal(signal.SIGTERM, terminate)
    try:
        return run_tests(arguments)
    except KeyboardInterrupt:
        return 130
    except OSError as error:
        print(f"Could not run package tests: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
