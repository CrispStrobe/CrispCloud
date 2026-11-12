#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compile the package's real DOC and CFB conversion acceptance checks to JS.

Requires an already installed Dart SDK, Node.js, and resolved package_config.json.
Does not resolve packages, use Flutter, access the network, or download tools.
Generated Dart/JavaScript files stay temporary and are removed on completion.
"""

import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default=shutil.which("dart"))
    parser.add_argument("--node", default=shutil.which("node"))
    args = parser.parse_args()
    if not args.dart or not args.node:
        parser.error("Provide paths to the already installed Dart and Node executables")

    repository = Path(__file__).resolve().parents[1]
    packages = repository / ".dart_tool/package_config.json"
    if not packages.is_file():
        parser.error("The package needs an existing resolved package_config.json")
    fixture = repository / "test/fixtures/word_native/formatting.doc"
    encoded = base64.b64encode(fixture.read_bytes()).decode("ascii")
    helper = (repository / "tool/web_acceptance.dart").as_uri()
    media_helper = (repository / "tool/media_web_acceptance.dart").as_uri()
    environment = dict(os.environ, CI="true")

    with tempfile.TemporaryDirectory(prefix="legacy-doc-web-", dir=packages.parent) as directory:
        temporary = Path(directory)
        source = temporary / "acceptance.dart"
        output = temporary / "acceptance.js"
        source.write_text(
            "import 'dart:convert';\n"
            f"import {json.dumps(helper)};\n"
            f"import {json.dumps(media_helper)};\n"
            "void main() {\n"
            f"  final result = verifyWebConversion(base64Decode('{encoded}'));\n"
            "  print('Legacy DOC JavaScript acceptance passed: ${jsonEncode(result)}');\n"
            "  print('Media JavaScript acceptance passed: ${jsonEncode(verifyMediaWebAcceptance())}');\n"
            "}\n",
            encoding="utf-8",
        )
        subprocess.run(
            [args.dart, "compile", "js", "--packages=" + str(packages),
             "-O1", "-o", str(output), str(source)],
            cwd=repository, env=environment, check=True, timeout=180,
        )
        subprocess.run(
            [args.node, "-e", "globalThis.self=globalThis; require(process.argv[1]);", str(output)],
            cwd=repository, env=environment, check=True, timeout=60,
        )


if __name__ == "__main__":
    main()
