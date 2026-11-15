import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

// Word 98 for the Macintosh writes the Word 97 format with nFib 0x00C2
// instead of 0x00C1. Those files used to be refused as "older Word binary
// version" although their layout is identical.
void main() {
  test('nFib 0x00C2 reads exactly like 0x00C1', () {
    var checked = 0;
    for (final file in Directory(
      'test/fixtures/word_native',
    ).listSync().whereType<File>()) {
      if (!file.path.endsWith('.doc')) continue;
      final original = file.readAsBytesSync();
      // Only fixtures whose WordDocument stream starts in sector 0.
      final fib = ByteData.sublistView(original, 512);
      if (fib.getUint16(0, Endian.little) != 0xa5ec ||
          fib.getUint16(2, Endian.little) != 0x00c1) {
        continue;
      }
      final String expected;
      final Map<String, String> expectedDocx;
      try {
        expected = extractLegacyWordText(original);
        expectedDocx = _parts(convertLegacyWord(original).bytes);
      } on FormatException {
        continue;
      }
      final mac = Uint8List.fromList(original);
      ByteData.sublistView(mac, 512).setUint16(2, 0x00c2, Endian.little);
      expect(extractLegacyWordText(mac), expected, reason: file.path);
      // Identical package; only the evidence manifest records the source
      // FIB version (provenance).
      final macParts = _parts(convertLegacyWord(mac).bytes);
      expect(
        macParts['word/evidence/manifest.json'] ?? '',
        contains('"fibVersion":194'),
        reason: file.path,
      );
      macParts.updateAll(
        (_, xml) => xml.replaceAll('"fibVersion":194', '"fibVersion":193'),
      );
      expect(macParts, expectedDocx, reason: file.path);
      checked++;
    }
    expect(checked, greaterThanOrEqualTo(3));
  });
}

Map<String, String> _parts(Uint8List docx) => {
  for (final file in ZipDecoder().decodeBytes(docx).files)
    file.name: String.fromCharCodes(file.content as List<int>),
};
