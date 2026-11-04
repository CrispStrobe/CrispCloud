#!/usr/bin/env python3
"""Format the new PDF integration and locally patched vendor files.

Existing application files keep their surrounding style. Vendor edits use the
upstream Dart 3.5 formatter style, avoiding a wholesale third-party rewrite.
Without --write this is a read-only formatting check.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_PATTERNS = (
    "lib/l10n/pdf_editor_strings.dart",
    "lib/services/pdf_*.dart",
    "lib/widgets/pdf_editor_dialog.dart",
    "test/pdf_*.dart",
    "test/panel_file_origin_test.dart",
    "test/support/pdf_editor_fixture.dart",
    "test/widget/pdf_editor_dialog_test.dart",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    app = sorted({str(path.relative_to(ROOT)) for pattern in APP_PATTERNS
                  for path in ROOT.glob(pattern)})
    vendor = {
        str(path.relative_to(ROOT))
        for pattern in (
            "packages/dart_pdf_editor/test/**/*.dart",
            "packages/dart_pdf_editor_secure_storage/lib/**/*.dart",
            "packages/dart_pdf_editor_secure_storage/test/**/*.dart",
        )
        for path in ROOT.glob(pattern)
    }
    # The maintained patch is also the inventory of modified upstream Dart.
    patch = ROOT / "packages/dart_pdf_editor/UPSTREAM.patch"
    for line in patch.read_text().splitlines():
        if line.startswith("+++ b/") and line.endswith(".dart"):
            path = line[len("+++ b/"):]
            if (ROOT / path).is_file():
                vendor.add(path)
    result = 0
    for files, version in ((app, "3.13"), (sorted(vendor), "3.5")):
        if not files:
            continue
        command = ["dart", "format", f"--language-version={version}"]
        if not args.write:
            command += ["--output=none", "--set-exit-if-changed"]
        completed = subprocess.run(command + files, cwd=ROOT, check=False)
        if completed.returncode != 0:
            result = 1
    raise SystemExit(result)


if __name__ == "__main__":
    main()
