import 'dart:convert';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(latin1.encode(s));

void main() {
  final cases = <String, (Uint8List, LegacyWordFileKind)>{
    'rtf': (_b('{\\rtf1\\ansi Hello}'), LegacyWordFileKind.rtf),
    'pdf': (_b('%PDF-1.7\n%\xe2\xe3\xcf\xd3\n1 0 obj'), LegacyWordFileKind.pdf),
    'pdf after junk': (_b('\r\n\r\n%PDF-1.4\n'), LegacyWordFileKind.pdf),
    'docx': (
      Uint8List.fromList([0x50, 0x4B, 3, 4, 20, 0, 6, 0]),
      LegacyWordFileKind.zip,
    ),
    'mhtml': (
      _b(
        'MIME-Version: 1.0\r\nContent-Type: multipart/related; boundary="x"\r\n',
      ),
      LegacyWordFileKind.mhtml,
    ),
    'word html': (
      _b('<html xmlns:o="urn:schemas-microsoft-com:office:office">\n<head>'),
      LegacyWordFileKind.html,
    ),
    'word 2003 xml': (
      _b(
        '<?xml version="1.0"?>\n<?mso-application progid="Word.Document"?>\n<w:wordDocument>',
      ),
      LegacyWordFileKind.wordXml,
    ),
    'word for dos': (
      Uint8List.fromList([0x31, 0xBE, 0, 0, 0, 0xAB, 0, 0, 0, 0, 0, 0]),
      LegacyWordFileKind.wordForDos,
    ),
    'word 2': (
      Uint8List.fromList([0xDB, 0xA5, 0x2D, 0, 0, 0, 9, 4]),
      LegacyWordFileKind.wordForDos,
    ),
    'wordperfect': (
      Uint8List.fromList([0xFF, 0x57, 0x50, 0x43, 16, 0, 0, 0]),
      LegacyWordFileKind.wordPerfect,
    ),
    'text': (
      _b('Dear colleagues,\r\nthe meeting moves.\r\n'),
      LegacyWordFileKind.text,
    ),
    'utf-16 html': (
      Uint8List.fromList([
        0xFF,
        0xFE,
        for (final c in '<html><body>'.codeUnits) ...[c, 0],
      ]),
      LegacyWordFileKind.html,
    ),
    'owner lock file': (
      Uint8List.fromList([
        ...[5, ...'Alice'.codeUnits],
        ...List.filled(162 - 6, 0x20),
      ]),
      LegacyWordFileKind.lockFile,
    ),
    'empty': (Uint8List(0), LegacyWordFileKind.empty),
    'zero filled': (Uint8List(39424), LegacyWordFileKind.zeroFilled),
    'binary noise': (
      Uint8List.fromList([1, 2, 3, 0, 200, 7, 0, 9]),
      LegacyWordFileKind.unknown,
    ),
  };
  for (final entry in cases.entries) {
    test('sniffs ${entry.key}', () {
      expect(sniffLegacyWordFile(entry.value.$1), entry.value.$2);
    });
  }

  test('the parser names the real format instead of failing generically', () {
    final pdf = Uint8List.fromList([
      ...latin1.encode('%PDF-1.7\n'),
      ...List.filled(600, 0x20),
    ]);
    expect(
      () => parseLegacyWordDocument(pdf),
      throwsA(
        isA<LegacyWordNotCompoundException>()
            .having((e) => e.kind, 'kind', LegacyWordFileKind.pdf)
            .having(
              (e) => e.message,
              'message',
              startsWith('Not a compound document'),
            )
            .having((e) => e.message, 'message', contains('PDF')),
      ),
    );
    // Still a FormatException for existing callers.
    expect(() => parseLegacyWordDocument(pdf), throwsFormatException);
  });

  test('a truncated compound header is reported as truncated', () {
    final short = Uint8List.fromList([
      0xD0,
      0xCF,
      0x11,
      0xE0,
      0xA1,
      0xB1,
      0x1A,
      0xE1,
      0,
      0,
    ]);
    expect(
      () => parseLegacyWordDocument(short),
      throwsA(
        isA<LegacyWordNotCompoundException>().having(
          (e) => e.message,
          'm',
          contains('truncated'),
        ),
      ),
    );
  });
}
