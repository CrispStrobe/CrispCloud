#!/usr/bin/env python3
"""Compile portable DOC/RTF/PPT/MSG readers to JavaScript with real fixtures.

Requires an existing Dart SDK, Node.js and resolved package_config.json. No
network access, package resolution, Flutter web build, or downloads are used.
Generated Dart/JavaScript files stay temporary and are removed at completion.
"""

import argparse
import base64
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


SMOKE_SOURCE = r'''
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/legacy_powerpoint_document.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:crisp_cloud/services/outlook_rtf_compression.dart';
import 'package:crisp_cloud/services/rtf_document.dart';

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void main() {
  final word = parseLegacyWordDocument(Uint8List.fromList(base64.decode('__DOC_BASE64__')));
  check(word.plainText.contains('Unicode café — 東京 😀.'), 'DOC logical Unicode text');
  check(word.blocks.whereType<LegacyWordTable>().single.rows.length == 2, 'DOC referenced table structure');
  final red = word.blocks.whereType<LegacyWordParagraph>()
      .expand((paragraph) => paragraph.runs).firstWhere((run) => run.text == 'Bold red text');
  check(red.style.bold && red.style.fontSizeHalfPoints == 36 && red.style.colorHex?.toUpperCase() == 'C02030', 'DOC character formatting');
  check(word.sections.isNotEmpty, 'DOC section layout');

  final fixture = Uint8List.fromList(GZipDecoder().decodeBytes(base64.decode('__PPT_BASE64__')));
  final ppt = extractLegacyPowerPoint(fixture);
  check(ppt.slides.length == 2, 'Current PPT slide count');
  check(ppt.slides.first.text == 'Current title 世界\nFirst body paragraph\nSecond body paragraph\nIndependent shape café', 'PPT current Unicode and shape text');
  check(ppt.slides.last.text == 'Second current slide\nCurrent final body', 'PPT slide order');
  check(!ppt.plainText.contains('SPEAKER NOTES'), 'PPT notes exclusion');

  final rtf = parseRtfDocument(Uint8List.fromList(ascii.encode(r'{\rtf1\ansi\uc0\b\u-10179\b0\u-8704  text\par{\object{\objdata 1234}}{\*\unknown hidden}}')));
  check(rtf.plainText == '😀 text', 'RTF Unicode and destination handling');
  check(rtf.html.contains('<strong>😀</strong> text'), 'RTF surrogate run normalization');

  // Microsoft's published MS-OXRTFCP overlapping-match golden vector and CRC.
  final packet = Uint8List.fromList([
    0x1a,0,0,0,0x1c,0,0,0,0x4c,0x5a,0x46,0x75,0xe2,0xd4,0x4b,0x51,
    0x41,0,4,0x20,0x57,0x58,0x59,0x5a,0x0d,0x6e,0x7d,1,0x0e,0xb0,
  ]);
  check(parseRtfDocument(decompressOutlookRtf(packet)).plainText == 'WXYZWXYZWXYZWXYZWXYZ', 'MSG compressed RTF golden vector');
  packet[18] ^= 1;
  var rejected = false;
  try {
    decompressOutlookRtf(packet);
  } on OutlookRtfException catch (error) {
    rejected = error.code == OutlookRtfErrorCode.malformed;
  }
  check(rejected, 'MSG CRC corruption rejection');
  print('Portable Office JavaScript smoke passed: DOC formatting/tables/sections, current PPT slides, RTF Unicode/formatting, MSG RTF decompression and CRC.');
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default=shutil.which("dart"))
    parser.add_argument("--node", default=shutil.which("node"))
    args = parser.parse_args()
    if not args.dart or not args.node:
        parser.error("Provide paths to the already-installed Dart and Node executables")
    repository = Path(__file__).resolve().parents[1]
    packages = repository / ".dart_tool/package_config.json"
    if not packages.is_file():
        parser.error("The repository needs an existing package_config.json")
    fixture = repository / "test/fixtures/legacy_powerpoint/current-slides.ppt.gz"
    encoded = base64.b64encode(fixture.read_bytes()).decode("ascii")
    word_encoded = base64.b64encode(
        (repository / "test/fixtures/word_native/formatting.doc").read_bytes()
    ).decode("ascii")
    with tempfile.TemporaryDirectory(prefix="portable-office-web-", dir=packages.parent) as temporary:
        root = Path(temporary)
        source = root / "smoke.dart"
        output = root / "smoke.js"
        source.write_text(SMOKE_SOURCE.replace("__PPT_BASE64__", encoded)
                          .replace("__DOC_BASE64__", word_encoded), encoding="utf-8")
        environment = dict(os.environ, CI="true")
        subprocess.run([args.dart, "compile", "js", "--packages=" + str(packages),
                        "-O1", "-o", str(output), str(source)],
                       cwd=repository, env=environment, check=True, timeout=180)
        subprocess.run([args.node, "-e", "globalThis.self=globalThis; require(process.argv[1]);", str(output)],
                       cwd=repository, env=environment, check=True, timeout=30)


if __name__ == "__main__":
    main()
