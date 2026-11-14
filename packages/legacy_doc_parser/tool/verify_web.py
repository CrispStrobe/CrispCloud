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
    fields_helper = (repository / "tool/nested_field_web_acceptance.dart").as_uri()
    stories_helper = (repository / "tool/story_unicode_web_acceptance.dart").as_uri()
    text_unicode_helper = (repository / "tool/text_unicode_web_acceptance.dart").as_uri()
    compound_helper = (repository / "tool/compound_web_acceptance.dart").as_uri()
    directory_helper = (repository / "tool/compound_directory_web_acceptance.dart").as_uri()
    ownership_helper = (repository / "tool/compound_ownership_web_acceptance.dart").as_uri()
    list_metadata_helper = (repository / "tool/list_metadata_web_acceptance.dart").as_uri()
    public_fields_helper = (repository / "tool/public_field_web_acceptance.dart").as_uri()
    public_metafiles_helper = (repository / "tool/public_metafile_web_acceptance.dart").as_uri()
    public_compound_helper = (repository / "tool/public_compound_web_acceptance.dart").as_uri()
    extra_helpers = [
        ("Public note ownership", "public_note_reference_web_acceptance.dart", "verifyPublicNoteReferenceWebAcceptance"),
        ("Compound generated matrix", "compound_property_acceptance.dart", "verifyCompoundPropertyAcceptance"),
        ("Generated field trees", "generated_field_tree_web_acceptance.dart", "verifyGeneratedFieldTreeWebAcceptance"),
        ("Public formatting", "public_formatting_web_acceptance.dart", "verifyPublicFormattingWebAcceptance"),
        ("Public table formatting", "public_table_formatting_web_acceptance.dart", "verifyPublicTableFormattingWebAcceptance"),
        ("Binary scalar domains", "scalar_sprm_web_acceptance.dart", "verifyScalarSprmWebAcceptance"),
        ("Literal list labels", "list_literal_web_acceptance.dart", "verifyListLiteralWebAcceptance"),
        ("List label visibility", "list_visibility_web_acceptance.dart", "verifyListVisibilityWebAcceptance"),
        ("List marker formatting", "list_marker_style_web_acceptance.dart", "verifyListMarkerStyleWebAcceptance"),
        ("Field visibility", "field_visibility_web_acceptance.dart", "verifyFieldVisibilityWebAcceptance"),
        ("Cached field mode", "cached_field_web_acceptance.dart", "verifyCachedFieldWebAcceptance"),
        ("Cached field structure", "cached_field_structure_web_acceptance.dart", "verifyCachedFieldStructureWebAcceptance"),
        ("Display field revision evidence", "display_field_evidence_web_acceptance.dart", "verifyDisplayFieldEvidenceWebAcceptance"),
        ("Source field marker formatting", "field_marker_formatting_web_acceptance.dart", "verifyFieldMarkerFormattingWebAcceptance"),
        ("Source field instruction visibility", "field_instruction_visibility_web_acceptance.dart", "verifyFieldInstructionVisibilityWebAcceptance"),
    ]
    extra_imports = "".join(f"import {json.dumps((repository / 'tool' / path).as_uri())};\n"
                            for _, path, _ in extra_helpers)
    extra_calls = "".join(f"  print('{label} JavaScript acceptance passed: ${{jsonEncode({function}())}}');\n"
                          for label, _, function in extra_helpers)
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
            f"import {json.dumps(fields_helper)};\n"
            f"import {json.dumps(stories_helper)};\n"
            f"import {json.dumps(text_unicode_helper)};\n"
            f"import {json.dumps(compound_helper)};\n"
            f"import {json.dumps(directory_helper)};\n"
            f"import {json.dumps(ownership_helper)};\n"
            f"import {json.dumps(list_metadata_helper)};\n"
            f"import {json.dumps(public_fields_helper)};\n"
            f"import {json.dumps(public_metafiles_helper)};\n"
            f"import {json.dumps(public_compound_helper)};\n"
            f"{extra_imports}"
            "void main() {\n"
            f"  final result = verifyWebConversion(base64Decode('{encoded}'));\n"
            "  print('Legacy DOC JavaScript acceptance passed: ${jsonEncode(result)}');\n"
            "  print('Media JavaScript acceptance passed: ${jsonEncode(verifyMediaWebAcceptance())}');\n"
            "  print('Nested field JavaScript acceptance passed: ${jsonEncode(verifyNestedFieldWebAcceptance())}');\n"
            "  print('Story Unicode JavaScript acceptance passed: ${jsonEncode(verifyStoryUnicodeWebAcceptance())}');\n"
            "  print('Text Unicode JavaScript acceptance passed: ${jsonEncode(verifyTextUnicodeWebAcceptance())}');\n"
            "  print('Compound allocation JavaScript acceptance passed: ${jsonEncode(verifyCompoundAllocationWebCases())}');\n"
            "  print('Compound directory JavaScript acceptance passed: ${jsonEncode(verifyCompoundDirectoryWebCases())}');\n"
            "  print('Compound ownership JavaScript acceptance passed: ${jsonEncode(verifyCompoundOwnershipWebCases())}');\n"
            "  print('List metadata JavaScript acceptance passed: ${jsonEncode(verifyListMetadataWebAcceptance())}');\n"
            "  print('Public field JavaScript acceptance passed: ${jsonEncode(verifyPublicFieldWebAcceptance())}');\n"
            "  print('Public metafile JavaScript acceptance passed: ${jsonEncode(verifyPublicMetafileWebAcceptance())}');\n"
            "  print('Public compound JavaScript acceptance passed: ${jsonEncode(verifyPublicCompoundWebAcceptance())}');\n"
            f"{extra_calls}"
            "  print('Ink budget JavaScript acceptance passed: ${jsonEncode(verifyInkBudgetWebAcceptance())}');\n"
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
