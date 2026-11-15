// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:test/test.dart';

// Word 6.0 / Word 95 files (wIdent 0xA5DC) were refused outright. Their
// main text is now imported (text only), from fcMin or, in fast-saved
// files, through the piece table in the WordDocument stream.

Uint8List _word6(
  List<int> text, {
  int nFib = 101,
  bool encrypted = false,
  bool mac = false,
  List<(int start, int length)>? pieces,
}) {
  const textAt = 0x300;
  final word = Uint8List(textAt + text.length + 0x100);
  final fib = ByteData.sublistView(word);
  fib.setUint16(0, 0xa5dc, Endian.little);
  fib.setUint16(2, nFib, Endian.little);
  fib.setUint16(
    10,
    (pieces != null ? 0x0004 : 0) | (encrypted ? 0x0100 : 0),
    Endian.little,
  );
  fib.setUint16(0x14, mac ? 256 : 0, Endian.little);
  fib.setUint32(0x18, textAt, Endian.little);
  fib.setUint32(0x1c, textAt + text.length, Endian.little);
  fib.setUint32(0x34, text.length, Endian.little);
  word.setAll(textAt, text);
  if (pieces != null) {
    // CLX after the text: Pcdt with the given (fc, length) pieces in CP order.
    final clxAt = textAt + text.length + 8;
    final n = pieces.length;
    final clx = ByteData.sublistView(word, clxAt);
    clx.setUint8(0, 2);
    clx.setUint32(1, 4 * (n + 1) + 8 * n, Endian.little);
    var cp = 0;
    for (var i = 0; i < n; i++) {
      clx.setUint32(5 + i * 4, cp, Endian.little);
      cp += pieces[i].$2;
    }
    clx.setUint32(5 + n * 4, cp, Endian.little);
    for (var i = 0; i < n; i++) {
      clx.setUint32(
        5 + (n + 1) * 4 + i * 8 + 2,
        textAt + pieces[i].$1,
        Endian.little,
      );
    }
    fib.setUint32(0x1a2, clxAt, Endian.little);
    fib.setUint32(0x1a6, 5 + 4 * (n + 1) + 8 * n, Endian.little);
  }
  return (CfbfWriter()..addStream('WordDocument', word)).build();
}

List<int> _ansi(String s) => s.codeUnits;

void main() {
  test('reads Windows-1252 text and keeps field results', () {
    final bytes = _word6([
      ..._ansi('Price: 5 '),
      0x80, // €
      ..._ansi(' '),
      0x93, ..._ansi('quoted'), 0x94,
      ..._ansi('\r'),
      0x13, ..._ansi(' DATE '), 0x14, ..._ansi('1.1.1996'), 0x15,
      ..._ansi('\r'),
    ]);
    expect(extractLegacyWordText(bytes), 'Price: 5 € “quoted”\n1.1.1996');
  });

  test('fast-saved files are read through their piece table', () {
    // Stored "worldHello " but the pieces put "Hello " first.
    final bytes = _word6(
      _ansi('worldHello \r'),
      pieces: [(5, 6), (0, 5), (11, 1)],
    );
    expect(extractLegacyWordText(bytes), 'Hello world');
  });

  test('Macintosh files are decoded as Mac Roman', () {
    final bytes = _word6([0x8a, 0x9a, 0xa7, ..._ansi('\r')], mac: true);
    expect(extractLegacyWordText(bytes), 'äöß');
  });

  test('encrypted and pre-Word-6 files are still refused', () {
    expect(
      () => extractLegacyWordText(_word6(_ansi('x\r'), encrypted: true)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'm',
          contains('encrypted'),
        ),
      ),
    );
    expect(
      () => extractLegacyWordText(_word6(_ansi('x\r'), nFib: 53)),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'm', contains('older')),
      ),
    );
  });

  test('conversion imports the text with recover, refuses without', () {
    final bytes = _word6(_ansi('First paragraph\rSecond\r'));
    expect(() => convertLegacyWord(bytes), throwsFormatException);
    final conversion = convertLegacyWord(bytes, recover: true);
    expect(conversion.recoveredTextOnly, isTrue);
    final xml = String.fromCharCodes(
      ZipDecoder()
              .decodeBytes(conversion.bytes)
              .findFile('word/document.xml')!
              .content
          as List<int>,
    );
    expect(xml, contains('First paragraph'));
    expect(xml, contains('Second'));
  });
}
