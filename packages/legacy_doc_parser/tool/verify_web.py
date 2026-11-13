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
    ink_helper = (repository / "tool/ink_web_acceptance.dart").as_uri()
    symbol_helper = (repository / "tool/symbol_web_acceptance.dart").as_uri()
    field_helper = (repository / "tool/field_metadata_web_acceptance.dart").as_uri()
    field_cases = [
        {"name": name, "base64": base64.b64encode(
            (repository / "test/fixtures/word_native" / filename).read_bytes()).decode("ascii")}
        for name, filename in (("external", "external-hyperlinks-native.doc"),
                               ("reference", "reference-hyperlink-native.doc"))
    ]
    encoded_fields = base64.b64encode(json.dumps(field_cases).encode()).decode("ascii")
    font_charset_helper = (repository / "tool/font_charset_web_acceptance.dart").as_uri()
    ink_cases = []
    for source in sorted((repository / "test/fixtures/ink_wpf").glob("*/*.isf")):
        snapshot = source.with_name(source.name.replace(".roundtrip.isf", ".second-reloaded.json")
                                    if source.name.endswith(".roundtrip.isf")
                                    else source.name.replace(".isf", ".reloaded.json"))
        ink_cases.append({"path": source.relative_to(repository).as_posix(),
                          "base64": base64.b64encode(source.read_bytes()).decode("ascii"),
                          "expected": json.loads(snapshot.read_bytes())})
    encoded_ink = base64.b64encode(json.dumps(ink_cases).encode()).decode("ascii")
    ink_header_cases = []
    for source in sorted((repository / "test/fixtures/ink_wpf_headers").glob("*/*.isf")):
        snapshot = source.with_name("second-reloaded.json" if source.name == "roundtrip.isf"
                                    else "reloaded.json")
        ink_header_cases.append({"path": source.relative_to(repository).as_posix(),
                                 "base64": base64.b64encode(source.read_bytes()).decode("ascii"),
                                 "expected": json.loads(snapshot.read_bytes())})
    encoded_ink_headers = base64.b64encode(json.dumps(ink_header_cases).encode()).decode("ascii")
    environment = dict(os.environ, CI="true")

    with tempfile.TemporaryDirectory(prefix="legacy-doc-web-", dir=packages.parent) as directory:
        temporary = Path(directory)
        source = temporary / "acceptance.dart"
        output = temporary / "acceptance.js"
        source.write_text(
            "import 'dart:convert';\n"
            f"import {json.dumps(helper)};\n"
            f"import {json.dumps(media_helper)};\n"
            f"import {json.dumps(ink_helper)};\n"
            f"import {json.dumps(symbol_helper)};\n"
            f"import {json.dumps(field_helper)};\n"
            f"import {json.dumps(font_charset_helper)};\n"
            "void main() {\n"
            f"  final result = verifyWebConversion(base64Decode('{encoded}'));\n"
            "  print('Legacy DOC JavaScript acceptance passed: ${jsonEncode(result)}');\n"
            "  print('Media JavaScript acceptance passed: ${jsonEncode(verifyMediaWebAcceptance())}');\n"
            f"  final ink = verifyInkWebAcceptance(jsonDecode(utf8.decode(base64Decode('{encoded_ink}'))) as List);\n"
            "  print('Ink JavaScript acceptance passed: ${jsonEncode(ink)}');\n"
            f"  final inkHeaders = verifyInkWebAcceptance(jsonDecode(utf8.decode(base64Decode('{encoded_ink_headers}'))) as List, headerCases: true);\n"
            "  print('Ink header JavaScript acceptance passed: ${jsonEncode(inkHeaders)}');\n"
            "  print('Symbol JavaScript acceptance passed: ${jsonEncode(verifySymbolWebAcceptance())}');\n"
            f"  final fields = verifyFieldMetadataWebAcceptance(jsonDecode(utf8.decode(base64Decode('{encoded_fields}'))) as List);\n"
            "  print('Field metadata JavaScript acceptance passed: ${jsonEncode(fields)}');\n"
            "  print('Font charset JavaScript acceptance passed: ${jsonEncode(verifyFontCharsetWebAcceptance())}');\n"
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
