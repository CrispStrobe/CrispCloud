// SPDX-License-Identifier: MPL-2.0
// Literal binary revision records for the independent Open XML SDK gate.
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/list_word_fixture.dart';
import '../../test/support/story_word_fixture.dart';
import '../../test/support/structured_word_fixture.dart';

const _date = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);

Uint8List _numbering(bool insertion) {
  final record = Uint8List(128);
  final data = ByteData.sublistView(record);
  record[0] = insertion ? 0 : 1;
  data.setUint16(2, 1, Endian.little);
  data.setUint32(4, _date, Endian.little);
  if (!insertion) {
    record[8] = 1;
    record[17] = 2; // Lower Roman original marker.
    data.setUint32(28, 3, Endian.little);
    data.setUint16(64, 2, Endian.little);
    data.setUint16(66, 0, Endian.little);
    data.setUint16(68, 46, Endian.little);
  }
  return StructuredWordFixture(
    pieces: const [WordFixturePiece('Numbering review\r')],
    paragraphRuns: [
      WordFixtureFkpRun(
        8192,
        8192 + 'Numbering review\r'.length,
        properties: [
          ...wordSprm(0xc645, [128, ...record]),
          if (insertion) ...wordSprm(0x2443, [1]),
          ...wordSprm(0x460b, wordU16(1)),
          ...wordSprm(0x260a, [0]),
        ],
      ),
    ],
    extraTablePairs: {
      51: storyBookmarkNames(['Unknown', 'Alice']),
      73: listFixtureDefinitions([listFixtureLevel(format: 0, start: 9)]),
      74: listFixtureInstances(),
    },
  ).build(mutate: (word, _) => word.setUint32(158 + 73 * 8, 30, Endian.little));
}

Uint8List _displayField() {
  const text = 'A\x13 LISTNUM \x142.\x15B\r';
  final record = Uint8List(39), data = ByteData(39);
  data.setUint8(0, 1);
  data.setUint16(1, 1, Endian.little);
  data.setUint32(3, _date, Endian.little);
  data.setUint16(7, 2, Endian.little);
  data.setUint16(9, 49, Endian.little);
  data.setUint16(11, 46, Endian.little);
  record.setAll(0, data.buffer.asUint8List());
  final begin = text.indexOf('\x13'), end = text.indexOf('\x15');
  return StructuredWordFixture(
    pieces: const [WordFixturePiece(text)],
    characterRuns: [
      WordFixtureFkpRun(8192, 8192 + begin),
      WordFixtureFkpRun(
        8192 + begin,
        8193 + end,
        properties: wordSprm(0xca62, [39, ...record]),
      ),
      WordFixtureFkpRun(8193 + end, 8192 + text.length),
    ],
    extraTablePairs: {
      16: storyPlc(
        [begin, text.indexOf('\x14'), end, 0xffffffff],
        [19, 0, 20, 0, 21, 0x80],
      ),
      51: storyBookmarkNames(['Unknown', 'Alice']),
    },
  ).build();
}

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply an output directory.');
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  for (final entry in {
    'numbering-change': _numbering(false),
    'numbering-insertion': _numbering(true),
    'listnum-display-change': _displayField(),
  }.entries) {
    File('${root.path}/${entry.key}.doc').writeAsBytesSync(entry.value);
    File(
      '${root.path}/${entry.key}.docx',
    ).writeAsBytesSync(convertLegacyWordToStructuredDocx(entry.value).bytes);
  }
}
