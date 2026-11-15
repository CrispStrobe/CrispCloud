// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart'
    show CfbfException;
import 'package:test/test.dart';

import 'support/structured_word_fixture.dart';

const _body = 'Recovered body text\rSecond paragraph\r';
const _plainBody = 'Recovered body text\nSecond paragraph';

// Matches the host conversion failure: allocation metadata and the referenced
// WordDocument/CLX remain intact, but the first directory sector is zeroed.
// StructuredWordFixture also contains unreachable private bytes that must not
// be copied into recovered output.
Uint8List _damagedDirectory({int flags = 0x0200, bool eraseFib = false}) {
  final bytes =
      StructuredWordFixture(
        pieces: const [WordFixturePiece(_body)],
        flags: flags,
      ).build(
        mutate: eraseFib
            ? (word, _) => word.setUint16(0, 0, Endian.little)
            : null,
      );
  final header = ByteData.sublistView(bytes);
  final sectorSize = 1 << header.getUint16(30, Endian.little);
  final directory = header.getUint32(48, Endian.little);
  final start = sectorSize * (directory + 1);
  bytes.fillRange(start, start + sectorSize, 0);
  return bytes;
}

final _invalidRoot = isA<CfbfException>().having(
  (error) => error.message,
  'message',
  'Invalid compound root directory',
);

String _documentXml(LegacyWordStructuredConversion conversion) {
  final archive = ZipDecoder().decodeBytes(conversion.bytes);
  return utf8.decode(
    archive.findFile('word/document.xml')!.content as List<int>,
  );
}

void main() {
  test('a destroyed directory leaves only the referenced body recoverable', () {
    final bytes = _damagedDirectory();
    expect(() => parseLegacyWordDocument(bytes), throwsA(_invalidRoot));
    expect(recoverLegacyWordText(bytes), _plainBody);
    expect(recoverLegacyWordText(bytes), isNot(contains('PRIVATE')));
  });

  test('typed compound damage falls back to disclosed text-only DOCX', () {
    final bytes = _damagedDirectory();
    final original = Uint8List.fromList(bytes);
    final conversion = convertLegacyWord(
      bytes,
      recover: true,
      fieldMode: LegacyWordFieldMode.cachedResults,
    );
    expect(conversion.recoveredTextOnly, isTrue);
    expect(conversion.format, LegacyWordOutputFormat.docx);
    expect(conversion.fieldMode, LegacyWordFieldMode.cachedResults);
    expect(conversion.limitations, LegacyWordConversionLimitation.values);
    expect(conversion.preservedCounts, isEmpty);
    expect(conversion.signatureEvidenceParts, isEmpty);
    expect(conversion.signatureValidityClaimed, isFalse);
    final xml = _documentXml(conversion);
    expect(xml, contains('Recovered body text'));
    expect(xml, contains('Second paragraph'));
    expect(xml, isNot(contains('UNREFERENCED PRIVATE BYTES')));
    expect(bytes, orderedEquals(original));
  });

  test('structured DOCX compatibility entry point retains recovery status', () {
    final conversion = convertLegacyWordToStructuredDocx(
      _damagedDirectory(),
      recover: true,
    );
    expect(conversion.recoveredTextOnly, isTrue);
    expect(_documentXml(conversion), contains('Recovered body text'));
  });

  test(
    'default and explicit strict conversion still refuse directory damage',
    () {
      final bytes = _damagedDirectory();
      expect(() => convertLegacyWord(bytes), throwsA(_invalidRoot));
      expect(
        () => convertLegacyWord(bytes, recover: false),
        throwsA(_invalidRoot),
      );
      expect(
        () => convertLegacyWordToStructuredDocx(bytes),
        throwsA(_invalidRoot),
      );
    },
  );

  test('damaged directory cannot use text fallback for DOCM output', () {
    expect(
      () => convertLegacyWord(
        _damagedDirectory(),
        recover: true,
        format: LegacyWordOutputFormat.docm,
      ),
      throwsA(_invalidRoot),
    );
  });

  for (final flag in [0x0100, 0x8000]) {
    test(
      'damaged directory preserves encryption/obfuscation refusal $flag',
      () {
        final bytes = _damagedDirectory(flags: 0x0200 | flag);
        expect(recoverLegacyWordText(bytes), isNull);
        expect(
          () => convertLegacyWord(bytes, recover: true),
          throwsA(_invalidRoot),
        );
      },
    );
  }

  test(
    'damaged directory without a valid FIB cannot recover stray strings',
    () {
      final bytes = _damagedDirectory(eraseFib: true);
      expect(recoverLegacyWordText(bytes), isNull);
      expect(
        () => convertLegacyWord(bytes, recover: true),
        throwsA(_invalidRoot),
      );
    },
  );

  test('directory recovery does not bypass the 64 MiB input bound', () {
    final bytes = Uint8List(64 * 1024 * 1024 + 1)
      ..setAll(0, _damagedDirectory());
    expect(recoverLegacyWordText(bytes), isNull);
    expect(
      () => convertLegacyWord(bytes, recover: true),
      throwsFormatException,
    );
  });
}
