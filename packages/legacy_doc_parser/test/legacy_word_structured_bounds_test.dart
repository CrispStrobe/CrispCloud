// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/legacy_word_document.dart';
import 'package:test/test.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart' show CfbfWriter;

import 'support/structured_word_fixture.dart';

void main() {
  test('coalesces 32768 same-style pieces without repeated prefix copies', () {
    final document = parseLegacyWordDocument(_fragmentedBody(32768, 32));
    final paragraph = document.blocks.single as LegacyWordParagraph;
    expect(paragraph.runs, hasLength(1));
    expect(paragraph.runs.single.text.length, 32768 * 32);
    expect(paragraph.runs.single.text, everyElementCodeUnit(0x78));
    expect(document.plainText.length, 32768 * 32);
    expect((paragraph.startCp, paragraph.endCp), (0, 32768 * 32 + 1));
  });

  test('cached indirect properties remain subject to expansion limits', () {
    const references = 100;
    const rootLength = references * 6;
    const leafOffset = rootLength + 2;
    final root = <int>[
      for (var i = 0; i < references; i++)
        ...wordSprm(0x6646, wordU32(leafOffset)),
    ];
    final leaf = <int>[
      for (var i = 0; i < 4000; i++) ...wordSprm(0x2405, [1]),
    ];
    final source = _indirectDocument([
      ...wordU16(root.length),
      ...root,
      ...wordU16(leaf.length),
      ...leaf,
    ]);
    expect(
      () => parseLegacyWordDocument(source),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('complexity limit'),
        ),
      ),
    );
  });

  test(
    'follows bounded indirect PAPX and rejects a recursive Data reference',
    () {
      final properties = [
        ...wordSprm(0x2403, [2]),
        ...wordSprm(0x2406, [1]),
      ];
      final document = parseLegacyWordDocument(
        _indirectDocument([...wordU16(properties.length), ...properties]),
      );
      final paragraph = document.blocks.single as LegacyWordParagraph;
      expect(paragraph.style.alignment, LegacyWordAlignment.right);
      expect(paragraph.style.keepNext, isTrue);

      final cycle = wordSprm(0x6646, wordU32(0));
      expect(
        () => parseLegacyWordDocument(
          _indirectDocument([...wordU16(cycle.length), ...cycle]),
        ),
        throwsFormatException,
      );
    },
  );

  test('visible preview text omits hidden runs but the conversion model retains them', () {
    final source = StructuredWordFixture(
      pieces: const [WordFixturePiece('VisibleSECRETEnd\r')],
      characterRuns: [
        const WordFixtureFkpRun(8192, 8199),
        WordFixtureFkpRun(8199, 8205, properties: wordSprm(0x083c, [1])),
        const WordFixtureFkpRun(8205, 8209),
      ],
    ).build();
    final document = parseLegacyWordDocument(source);
    expect(document.plainText, 'VisibleEnd');
    expect(document.safeHtml, isNot(contains('SECRET')));
    final paragraph = document.blocks.single as LegacyWordParagraph;
    expect(
      paragraph.runs.singleWhere((run) => run.style.hidden).text,
      'SECRET',
    );
    expect(extractLegacyWordText(source), 'VisibleSECRETEnd');
  });
}

Matcher everyElementCodeUnit(int codeUnit) => predicate<String>(
  (text) => text.codeUnits.every((unit) => unit == codeUnit),
  'contains only the referenced character',
);

Uint8List _indirectDocument(List<int> data) => StructuredWordFixture(
  pieces: const [WordFixturePiece('Text\r')],
  paragraphRuns: [
    WordFixtureFkpRun(8192, 8197, properties: wordSprm(0x6646, wordU32(0))),
  ],
  extraStreams: {'Data': Uint8List.fromList(data)},
).build();

Uint8List _fragmentedBody(int pieces, int charactersPerPiece) {
  const textOffset = 8192;
  final length = pieces * charactersPerPiece + 1;
  final word = Uint8List(textOffset + length);
  final header = ByteData.sublistView(word);
  void u16(int at, int value) => header.setUint16(at, value, Endian.little);
  void u32(int at, int value) => header.setUint32(at, value, Endian.little);
  u16(0, 0xa5ec);
  u16(2, 0xc1);
  u16(10, 0x0200);
  u16(32, 14);
  u16(62, 22);
  u16(152, 93);
  u32(64, word.length);
  u32(76, length);
  word.fillRange(textOffset, word.length - 1, 0x78);
  word[word.length - 1] = 13;
  final recordCount = pieces + 1;
  final plc = Uint8List(4 + recordCount * 12);
  final pcd = ByteData.sublistView(plc);
  final recordsAt = (recordCount + 1) * 4;
  for (var index = 0; index < recordCount; index++) {
    final cp = index * charactersPerPiece;
    pcd.setUint32(index * 4, cp, Endian.little);
    pcd.setUint32(
      recordsAt + index * 8 + 2,
      0x40000000 | (textOffset + cp) * 2,
      Endian.little,
    );
  }
  pcd.setUint32(recordCount * 4, length, Endian.little);
  final clx = Uint8List.fromList([2, ...wordU32(plc.length), ...plc]);
  u32(154 + 33 * 8, 0);
  u32(158 + 33 * 8, clx.length);
  return (CfbfWriter()
        ..addStream('WordDocument', word)
        ..addStream('1Table', clx))
      .build();
}
