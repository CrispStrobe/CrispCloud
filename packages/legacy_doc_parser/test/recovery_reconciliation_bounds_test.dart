// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart'
    show CfbfException;
import 'package:test/test.dart';

import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

// A deliberately damaged compound container with an intact, explicitly
// referenced Word body and CLX. No heuristic string scan is involved.
Uint8List _rawRecovery({
  String text = 'Recovered body\r',
  int version = 0x00c1,
  int flags = 0,
  int? declaredExtent,
  int invalidCandidates = 0,
  bool decodeBeforeReject = false,
}) {
  const textAt = 1024;
  final wordSize = ((textAt + text.length + 511) ~/ 512) * 512 + 1024;
  final tableAt = 512 + wordSize;
  final candidateCount = invalidCandidates + 1;
  final fileSize = ((tableAt + candidateCount * 64 + 511) ~/ 512) * 512;
  final bytes = Uint8List(fileSize);
  bytes.setAll(0, const [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  final header = ByteData.sublistView(bytes);
  header.setUint16(30, 9, Endian.little);
  final fib = ByteData.sublistView(bytes, 512, tableAt);
  fib.setUint16(0, 0xa5ec, Endian.little);
  fib.setUint16(2, version, Endian.little);
  fib.setUint16(10, flags, Endian.little);
  fib.setUint16(32, 14, Endian.little);
  fib.setUint16(62, 22, Endian.little);
  fib.setUint32(64, declaredExtent ?? wordSize, Endian.little);
  fib.setUint32(76, text.length, Endian.little);
  fib.setUint16(152, 34, Endian.little);
  fib.setUint32(418, 0, Endian.little);
  final pieces = decodeBeforeReject ? 2 : 1;
  final pieceBytes = 4 + pieces * 12;
  fib.setUint32(422, 5 + pieceBytes, Endian.little);
  bytes.setAll(512 + textAt, text.codeUnits);
  for (var index = 0; index < candidateCount; index++) {
    final table = ByteData.sublistView(bytes, tableAt + index * 64);
    table.setUint8(0, 2);
    table.setUint32(1, pieceBytes, Endian.little);
    table.setUint32(5, 0, Endian.little);
    if (decodeBeforeReject) {
      table.setUint32(9, text.length - 1, Endian.little);
      table.setUint32(13, text.length, Endian.little);
      table.setUint32(19, 0x40000000 | textAt * 2, Endian.little);
      table.setUint32(
        27,
        index < invalidCandidates
            ? 0x80000000
            : 0x40000000 | (textAt + text.length - 1) * 2,
        Endian.little,
      );
    } else {
      table.setUint32(9, text.length, Endian.little);
      table.setUint32(
        15,
        index < invalidCandidates ? 0x80000000 : 0x40000000 | textAt * 2,
        Endian.little,
      );
    }
  }
  return bytes;
}

Uint8List _word6({
  required List<int> encoded,
  required int characters,
  bool unicode = false,
  bool complex = false,
  int charset = 0,
  int locale = 0,
}) {
  const textAt = 0x300;
  final word = Uint8List(textAt + encoded.length + 256);
  final fib = ByteData.sublistView(word);
  fib.setUint16(0, 0xa5dc, Endian.little);
  fib.setUint16(2, 101, Endian.little);
  fib.setUint16(6, locale, Endian.little);
  fib.setUint16(10, (unicode ? 0x1000 : 0) | (complex ? 4 : 0), Endian.little);
  fib.setUint16(0x14, charset, Endian.little);
  fib.setUint32(0x18, textAt, Endian.little);
  fib.setUint32(0x1c, textAt + encoded.length, Endian.little);
  fib.setUint32(0x34, characters, Endian.little);
  word.setAll(textAt, encoded);
  if (complex) {
    final clxAt = textAt + encoded.length + 8;
    final clx = ByteData.sublistView(word, clxAt);
    clx.setUint8(0, 2);
    clx.setUint32(1, 16, Endian.little);
    clx.setUint32(5, 0, Endian.little);
    clx.setUint32(9, characters, Endian.little);
    clx.setUint32(15, textAt, Endian.little);
    fib.setUint32(0x1a2, clxAt, Endian.little);
    fib.setUint32(0x1a6, 21, Endian.little);
  }
  return (CfbfWriter()..addStream('WordDocument', word)).build();
}

List<int> _utf16(String value) => [
  for (final code in value.codeUnits) ...[code & 0xff, code >> 8],
];

void main() {
  test(
    'explicit DOCX recovery handles compound parser errors; strict mode preserves them',
    () {
      final bytes = StructuredWordFixture(
        pieces: const [WordFixturePiece('Recovered body\r')],
      ).build();
      final header = ByteData.sublistView(bytes);
      final sectorSize = 1 << header.getUint16(30, Endian.little);
      final directoryAt =
          sectorSize * (header.getUint32(48, Endian.little) + 1);
      bytes.fillRange(directoryAt, directoryAt + sectorSize, 0);
      final before = Uint8List.fromList(bytes);
      expect(() => convertLegacyWord(bytes), throwsA(isA<CfbfException>()));
      final recovered = convertLegacyWord(bytes, recover: true);
      expect(recovered.recoveredTextOnly, isTrue);
      expect(recovered.bytes, isNotEmpty);
      expect(bytes, orderedEquals(before));
      expect(
        () => convertLegacyWord(
          bytes,
          recover: true,
          format: LegacyWordOutputFormat.docm,
        ),
        throwsA(isA<CfbfException>()),
      );
    },
  );
  test('bounded raw recovery still follows a valid referenced piece table', () {
    expect(recoverLegacyWordText(_rawRecovery()), 'Recovered body');
  });

  test('Word 98 Mac signature is retained in damaged-container recovery', () {
    expect(
      recoverLegacyWordText(_rawRecovery(version: 0x00c2)),
      'Recovered body',
    );
  });

  test('raw recovery respects the public 64 MiB input admission bound', () {
    final oversized = Uint8List(64 * 1024 * 1024 + 1)
      ..setAll(0, _rawRecovery());
    expect(recoverLegacyWordText(oversized), isNull);
    expect(
      () => convertLegacyWord(oversized, recover: true),
      throwsFormatException,
    );
  });

  for (final extent in [256, 1024 * 1024, 32 * 1024 * 1024 + 1]) {
    test('raw recovery does not ignore contradictory cbMac $extent', () {
      expect(
        recoverLegacyWordText(_rawRecovery(declaredExtent: extent)),
        isNull,
      );
    });
  }

  test('raw recovery bounds candidate validation attempts', () {
    final bytes = _rawRecovery(invalidCandidates: 4096);
    expect(recoverLegacyWordText(bytes) == null, isTrue);
  });

  test('raw recovery bounds cumulative text-decoding work', () {
    final bytes = _rawRecovery(
      text: '${'A' * 65535}\r',
      invalidCandidates: 128,
      decodeBeforeReject: true,
    );
    expect(recoverLegacyWordText(bytes) == null, isTrue);
  });

  for (final flags in [0x0100, 0x8000]) {
    test('raw recovery preserves encrypted/obfuscated refusal $flags', () {
      final bytes = _rawRecovery(flags: flags);
      expect(recoverLegacyWordText(bytes), isNull);
      expect(
        () => convertLegacyWord(bytes, recover: true),
        throwsFormatException,
      );
    });
  }

  for (final complex in [false, true]) {
    test('Word 6 Unicode body preserves UTF-16 with complex=$complex', () {
      const text = '€C🙂\r';
      final bytes = _word6(
        encoded: _utf16(text),
        characters: text.length,
        unicode: true,
        complex: complex,
        charset: 204,
        locale: 0x0419,
      );
      expect(extractLegacyWordText(bytes), '€C🙂');
      expect(convertLegacyWord(bytes, recover: true).recoveredTextOnly, isTrue);
    });
  }

  test('Word 6 Unicode rejects an isolated surrogate before conversion', () {
    final bytes = _word6(
      encoded: [0, 0xd8, 13, 0],
      characters: 2,
      unicode: true,
    );
    expect(() => extractLegacyWordText(bytes), throwsFormatException);
    expect(
      () => convertLegacyWord(bytes, recover: true),
      throwsFormatException,
    );
  });

  for (final (charset, locale) in [(204, 0), (0, 0x0419)]) {
    test(
      'Word 6 refuses an unsupported 8-bit charset/locale $charset/$locale',
      () {
        final bytes = _word6(
          encoded: [0xc0, 13],
          characters: 2,
          charset: charset,
          locale: locale,
        );
        expect(() => extractLegacyWordText(bytes), throwsFormatException);
        expect(
          () => convertLegacyWord(bytes, recover: true),
          throwsFormatException,
        );
      },
    );
  }

  test('Word 6 explicitly declared en-US ANSI keeps Windows-1252 text', () {
    final bytes = _word6(
      encoded: [0x80, 0xc4, 13],
      characters: 3,
      locale: 0x0409,
    );
    expect(extractLegacyWordText(bytes), '€Ä');
  });

  test('comment omission keeps a bookmark at the next story boundary', () {
    const main = 'A\x02\x05B\r';
    const comment = '\x05Note\r';
    const note = '\x02End note\r';
    final noteBase = main.length + comment.length + 1;
    final bytes = storyWordFixture(
      main: main,
      comments: '$comment\r',
      endnotes: '$note\r',
      tablePairs: {
        4: storyPlc([0, 0xffffffff], storyCommentRecord()),
        5: storyPlc([0, comment.length, 0xffffffff]),
        36: storyXst('Alice'),
        46: storyPlc([1, 0xffffffff], wordU16(1)),
        47: storyPlc([0, note.length, 0xffffffff]),
        21: storyBookmarkNames(['KeepNote']),
        22: storyPlc([noteBase, 0xffffffff], [...wordU16(0), ...wordU16(0)]),
        23: storyPlc([noteBase + note.length, 0xffffffff]),
      },
    );
    final document = parseLegacyWordDocument(bytes, recover: true);
    expect(document.warnings, contains(LegacyWordWarning.commentsOmitted));
    expect(document.bookmarks.map((bookmark) => bookmark.name), ['KeepNote']);
    expect(document.noteReferences, hasLength(1));
    expect(
      document.stories.where(
        (story) => story.kind == LegacyWordStoryKind.endnote,
      ),
      hasLength(1),
    );
    convertLegacyWordDocument(document);
  });
}
