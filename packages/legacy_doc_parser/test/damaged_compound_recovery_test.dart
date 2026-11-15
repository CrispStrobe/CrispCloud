import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

// Files whose compound directory, FAT and mini FAT were overwritten (an
// interrupted save or copy) are refused by Word and by the structured
// parser. With `recover`, their text is read from the intact WordDocument
// and table streams.

/// Overwrites every FAT sector, directory sector and the mini FAT with
/// arbitrary bytes, the way the damaged files in the wild look.
Uint8List _damage(Uint8List source) {
  final bytes = Uint8List.fromList(source);
  final header = ByteData.sublistView(bytes);
  final fatCount = header.getUint32(44, Endian.little);
  final sectors = <int>[
    for (var i = 0; i < fatCount && i < 109; i++)
      header.getUint32(76 + i * 4, Endian.little),
    header.getUint32(48, Endian.little), // first directory sector
    header.getUint32(60, Endian.little), // first mini FAT sector
  ];
  var seed = 7;
  for (final sector in sectors) {
    if (sector >= 0xFFFFFFFA) continue;
    final at = 512 + sector * 512;
    for (var i = 0; i < 512 && at + i < bytes.length; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      bytes[at + i] = seed >> 16 & 0xff;
    }
  }
  return bytes;
}

String _documentXml(Uint8List docx) {
  final archive = ZipDecoder().decodeBytes(docx);
  return String.fromCharCodes(
    archive.findFile('word/document.xml')!.content as List<int>,
  );
}

void main() {
  final fixtures =
      Directory('test/fixtures/word_native')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.doc'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('recovery reads the same text as the intact file', () {
    var recovered = 0;
    for (final file in fixtures) {
      final intact = file.readAsBytesSync();
      final String expected;
      try {
        expected = extractLegacyWordText(intact);
      } on FormatException {
        continue;
      }
      // On the intact file the recovery path must agree exactly.
      final direct = recoverLegacyWordText(intact);
      if (direct != null) expect(direct, expected, reason: file.path);
      final damaged = _damage(intact);
      expect(
        () => parseLegacyWordDocument(damaged),
        throwsFormatException,
        reason: file.path,
      );
      final text = recoverLegacyWordText(damaged);
      if (text == null) continue;
      expect(text, expected, reason: file.path);
      recovered++;
    }
    expect(recovered, greaterThan(fixtures.length ~/ 2));
  });

  test('convertLegacyWord(recover: true) falls back to the recovered text', () {
    for (final file in fixtures) {
      final intact = file.readAsBytesSync();
      final String expected;
      try {
        expected = extractLegacyWordText(intact);
      } on FormatException {
        continue;
      }
      if (expected.trim().length < 20) continue;
      final damaged = _damage(intact);
      if (recoverLegacyWordText(damaged) == null) continue;
      expect(() => convertLegacyWord(damaged), throwsFormatException);
      final conversion = convertLegacyWord(damaged, recover: true);
      expect(conversion.recoveredTextOnly, isTrue);
      expect(
        conversion.limitations,
        containsAll(LegacyWordConversionLimitation.values),
      );
      final xml = _documentXml(conversion.bytes);
      final firstWords = expected
          .split('\n')
          .firstWhere((line) => line.trim().length > 3)
          .trim();
      expect(
        xml,
        contains(
          firstWords
              .split('\t')
              .first
              .replaceAll('&', '&amp;')
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;'),
        ),
        reason: file.path,
      );
      return;
    }
    fail('no fixture was recoverable');
  });

  test('intact files never report a text-only recovery', () {
    final intact = fixtures.first.readAsBytesSync();
    expect(convertLegacyWord(intact, recover: true).recoveredTextOnly, isFalse);
  });

  test('files without a Word FIB are not recovered', () {
    final bytes = Uint8List(4096)
      ..setAll(0, const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
    ByteData.sublistView(bytes).setUint16(30, 9, Endian.little);
    expect(recoverLegacyWordText(bytes), isNull);
  });
}
