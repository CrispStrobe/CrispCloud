// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

/// Independently assembled MS-DOC structures, not output from the parser under
/// test. The deliberately sparse WordDocument permits logical CP order to
/// differ from physical FC order and keeps unreachable text outside the CLX.
///
/// References: MS-DOC §§2.4.1, 2.4.6, 2.8.5, 2.8.6, 2.8.26, 2.9.33,
/// 2.9.174–175, 2.9.215–216 and 2.9.271–274.
class StructuredWordFixture {
  StructuredWordFixture({
    required this.pieces,
    this.characterRuns = const [],
    this.paragraphRuns = const [],
    this.styles = const {0: WordFixtureStyle(name: 'Normal', builtinId: 0)},
    this.sections = const [],
    this.prcs = const [],
    this.extraTablePairs = const {},
    this.storyCounts = const {},
    this.extraStreams = const {},
    this.mainCharacterCount,
    this.languageId = 0x0409,
    this.flags = 0x0200,
  });

  static const characterFkpOffset = 4096;
  static const paragraphFkpOffset = 4608;

  final List<WordFixturePiece> pieces;
  final List<WordFixtureFkpRun> characterRuns;
  final List<WordFixtureFkpRun> paragraphRuns;
  final Map<int, WordFixtureStyle> styles;
  final List<WordFixtureSection> sections;
  final List<List<int>> prcs;
  final Map<int, List<int>> extraTablePairs;
  final Map<int, int> storyCounts;
  final Map<String, Uint8List> extraStreams;
  final int? mainCharacterCount;
  final int languageId;
  final int flags;

  Uint8List build({void Function(ByteData, Uint8List)? mutate}) {
    final word = Uint8List(32768);
    final data = ByteData.sublistView(word);
    void u16(int offset, int value) =>
        data.setUint16(offset, value, Endian.little);
    void u32(int offset, int value) =>
        data.setUint32(offset, value, Endian.little);
    u16(0, 0xa5ec);
    u16(2, 0x00c1);
    u16(6, languageId);
    u16(10, flags);
    u16(12, 0x00bf);
    u16(32, 14);
    u16(62, 22);
    u16(152, 93);
    u32(64, word.length);
    final cpCount = pieces.fold(0, (n, piece) => n + piece.text.length);
    u32(76, mainCharacterCount ?? cpCount);
    for (final entry in storyCounts.entries) {
      u32(64 + entry.key * 4, entry.value);
    }
    final physical = [...pieces]..sort((a, b) => a.offset.compareTo(b.offset));
    u32(24, physical.first.offset);
    u32(28, physical.last.endOffset);
    for (final piece in pieces) {
      assert(piece.offset >= 8192 && piece.endOffset < 30000);
      for (var i = 0; i < piece.text.length; i++) {
        if (piece.compressed) {
          assert(piece.text.codeUnitAt(i) <= 255);
          word[piece.offset + i] = piece.text.codeUnitAt(i);
        } else {
          u16(piece.offset + 2 * i, piece.text.codeUnitAt(i));
        }
      }
    }
    final unreachable = 'UNREFERENCED PRIVATE BYTES'.codeUnits;
    word.setRange(31000, 31000 + unreachable.length, unreachable);

    final table = BytesBuilder(copy: false)..add(Uint8List(16));
    void pair(int index, List<int> value) {
      u32(154 + index * 8, table.length);
      u32(158 + index * 8, value.length);
      table.add(value);
    }

    pair(1, _stylesheet(styles));
    final clx = BytesBuilder(copy: false);
    for (final prc in prcs) {
      clx.add([1, ...wordU16(prc.length), ...prc]);
    }
    final plc = Uint8List(4 + pieces.length * 12);
    final pcd = ByteData.sublistView(plc);
    final records = 4 * (pieces.length + 1);
    var cp = 0;
    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      pcd.setUint32(i * 4, cp, Endian.little);
      pcd.setUint32(
        records + i * 8 + 2,
        piece.compressed ? 0x40000000 | piece.offset * 2 : piece.offset,
        Endian.little,
      );
      pcd.setUint16(records + i * 8 + 6, piece.prm, Endian.little);
      cp += piece.text.length;
    }
    pcd.setUint32(pieces.length * 4, cp, Endian.little);
    clx.add([2, ...wordU32(plc.length), ...plc]);
    pair(33, clx.takeBytes());

    {
      final runs = _fillGaps(
        characterRuns.isNotEmpty
            ? characterRuns
            : [
                for (final piece in physical)
                  WordFixtureFkpRun(piece.offset, piece.endOffset),
              ],
      );
      word.setRange(
        characterFkpOffset,
        characterFkpOffset + 512,
        _fkp(runs, paragraph: false),
      );
      pair(12, [
        ...wordU32(runs.first.startFc),
        ...wordU32(runs.last.endFc),
        ...wordU32(characterFkpOffset ~/ 512),
      ]);
    }
    {
      final defaultRuns = <WordFixtureFkpRun>[];
      for (final piece in physical) {
        var start = piece.offset;
        final width = piece.compressed ? 1 : 2;
        for (var i = 0; i < piece.text.length; i++) {
          if (!const [7, 12, 13].contains(piece.text.codeUnitAt(i))) continue;
          final end = piece.offset + (i + 1) * width;
          defaultRuns.add(WordFixtureFkpRun(start, end));
          start = end;
        }
        if (start < piece.endOffset) {
          defaultRuns.add(WordFixtureFkpRun(start, piece.endOffset));
        }
      }
      final runs = _fillGaps(
        paragraphRuns.isNotEmpty ? paragraphRuns : defaultRuns,
      );
      word.setRange(
        paragraphFkpOffset,
        paragraphFkpOffset + 512,
        _fkp(runs, paragraph: true),
      );
      pair(13, [
        ...wordU32(runs.first.startFc),
        ...wordU32(runs.last.endFc),
        ...wordU32(paragraphFkpOffset ~/ 512),
      ]);
    }
    if (sections.isNotEmpty) {
      final sed = BytesBuilder(copy: false)..add(wordU32(0));
      for (final section in sections) {
        sed.add(wordU32(section.endCp));
      }
      var sepxOffset = 5632;
      for (final section in sections) {
        final sepx = [
          ...wordU16(section.properties.length),
          ...section.properties,
        ];
        word.setRange(sepxOffset, sepxOffset + sepx.length, sepx);
        sed.add([
          ...wordU16(0),
          ...wordU32(sepxOffset),
          ...wordU16(0),
          ...wordU32(0xffffffff),
        ]);
        sepxOffset += sepx.length;
      }
      pair(6, sed.takeBytes());
    }
    for (final entry in extraTablePairs.entries) {
      pair(entry.key, entry.value);
    }
    final tableBytes = table.takeBytes();
    mutate?.call(data, tableBytes);
    final writer = CfbfWriter()
      ..addStream('WordDocument', word)
      ..addStream((flags & 0x0200) != 0 ? '1Table' : '0Table', tableBytes)
      // A decoy proves that the FIB, not stream order, selects the table.
      ..addStream((flags & 0x0200) != 0 ? '0Table' : '1Table', Uint8List(4096));
    for (final entry in extraStreams.entries) {
      writer.addStream(entry.key, entry.value);
    }
    return writer.build();
  }
}

class WordFixturePiece {
  const WordFixturePiece(
    this.text, {
    this.offset = 8192,
    this.compressed = true,
    this.prm = 0,
  });
  final String text;
  final int offset;
  final bool compressed;
  final int prm;
  int get endOffset => offset + text.length * (compressed ? 1 : 2);
}

class WordFixtureFkpRun {
  const WordFixtureFkpRun(
    this.startFc,
    this.endFc, {
    this.properties = const [],
    this.styleIndex = 0,
  });
  final int startFc;
  final int endFc;
  final List<int> properties;
  final int styleIndex;
}

class WordFixtureStyle {
  const WordFixtureStyle({
    required this.name,
    this.builtinId = 0x0ffe,
    this.parentIndex = 0x0fff,
    this.character = false,
    this.table = false,
    this.tableProperties = const [],
    this.paragraphProperties = const [],
    this.characterProperties = const [],
  });
  final String name;
  final int builtinId;
  final int parentIndex;
  final bool character;
  final bool table;
  final List<int> tableProperties;
  final List<int> paragraphProperties;
  final List<int> characterProperties;
}

class WordFixtureSection {
  const WordFixtureSection(this.endCp, this.properties);
  final int endCp;
  final List<int> properties;
}

List<int> wordU16(int value) => [value & 255, (value >> 8) & 255];
List<int> wordU32(int value) => [...wordU16(value), ...wordU16(value >> 16)];
List<int> wordSprm(int opcode, List<int> operand) => [
  ...wordU16(opcode),
  ...operand,
];

/// A table row with two physical cells. Its first cell has two paragraphs;
/// neither its first row nor its first paragraph is implicitly a header.
Uint8List tableWordFixture({bool merged = false}) {
  final definition = <int>[
    2,
    ...wordU16(0),
    ...wordU16(1440),
    ...wordU16(3600),
    for (final flag in [merged ? 2 : 0, merged ? 1 : 0]) ...[
      ...wordU16(flag),
      ...wordU16(0),
      ...List<int>.filled(16, 0),
    ],
  ];
  return StructuredWordFixture(
    pieces: const [WordFixturePiece('A\rB\x07C\x07\x07After\r')],
    paragraphRuns: [
      for (final (start, end) in [(8192, 8194), (8194, 8196), (8196, 8198)])
        WordFixtureFkpRun(start, end, properties: wordSprm(0x2416, [1])),
      WordFixtureFkpRun(
        8198,
        8199,
        properties: [
          ...wordSprm(0x2416, [1]),
          ...wordSprm(0x2417, [1]),
          ...wordSprm(0xd608, [
            ...wordU16(definition.length + 1),
            ...definition,
          ]),
        ],
      ),
      const WordFixtureFkpRun(8199, 8205),
    ],
  ).build();
}

List<WordFixtureFkpRun> _fillGaps(List<WordFixtureFkpRun> source) {
  final sorted = [...source]..sort((a, b) => a.startFc.compareTo(b.startFc));
  final result = <WordFixtureFkpRun>[];
  for (final run in sorted) {
    assert(run.startFc < run.endFc);
    if (result.isNotEmpty) {
      assert(result.last.endFc <= run.startFc);
      if (result.last.endFc < run.startFc) {
        result.add(WordFixtureFkpRun(result.last.endFc, run.startFc));
      }
    }
    result.add(run);
  }
  return result;
}

Uint8List _fkp(List<WordFixtureFkpRun> runs, {required bool paragraph}) {
  assert(runs.length <= (paragraph ? 29 : 101));
  final bytes = Uint8List(512);
  final data = ByteData.sublistView(bytes);
  final descriptors = (runs.length + 1) * 4;
  var cursor = 510;
  for (var i = 0; i < runs.length; i++) {
    final run = runs[i];
    data.setUint32(i * 4, run.startFc, Endian.little);
    if (!paragraph && run.properties.isEmpty) continue;
    final payload = [
      if (paragraph) ...wordU16(run.styleIndex),
      ...run.properties,
    ];
    final record = paragraph
        ? (payload.length.isEven
              ? [0, payload.length ~/ 2, ...payload]
              : [(payload.length + 1) ~/ 2, ...payload])
        : [payload.length, ...payload];
    cursor = (cursor - record.length) & ~1;
    assert(cursor >= descriptors + runs.length * (paragraph ? 13 : 1));
    bytes.setRange(cursor, cursor + record.length, record);
    bytes[descriptors + i * (paragraph ? 13 : 1)] = cursor ~/ 2;
  }
  data.setUint32(runs.length * 4, runs.last.endFc, Endian.little);
  bytes[511] = runs.length;
  return bytes;
}

Uint8List _stylesheet(Map<int, WordFixtureStyle> styles) {
  final count = styles.keys.fold(15, (n, key) => key >= n ? key + 1 : n);
  final header = Uint8List(18);
  final data = ByteData.sublistView(header);
  data.setUint16(0, count, Endian.little);
  data.setUint16(2, 10, Endian.little);
  data.setUint16(4, 1, Endian.little);
  data.setUint16(6, 108, Endian.little);
  data.setUint16(8, 15, Endian.little);
  final output = BytesBuilder(copy: false)..add([...wordU16(18), ...header]);
  for (var index = 0; index < count; index++) {
    final style = styles[index];
    if (style == null) {
      output.add([0, 0]);
      continue;
    }
    final base = Uint8List(10);
    final fields = ByteData.sublistView(base);
    fields.setUint16(0, style.builtinId, Endian.little);
    fields.setUint16(
      2,
      (style.parentIndex << 4) |
          (style.table
              ? 3
              : style.character
              ? 2
              : 1),
      Endian.little,
    );
    fields.setUint16(
      4,
      style.table
          ? 3
          : style.character
          ? 1
          : 2,
      Endian.little,
    );
    final record = BytesBuilder(copy: false)
      ..add(base)
      ..add(wordU16(style.name.length));
    for (final unit in style.name.codeUnits) {
      record.add(wordU16(unit));
    }
    record.add([0, 0]);
    void upx(List<int> value) {
      record.add([...wordU16(value.length), ...value]);
      if (value.length.isOdd) record.addByte(0);
    }

    if (style.table) upx(style.tableProperties);
    if (!style.character) {
      upx([...wordU16(index), ...style.paragraphProperties]);
    }
    upx(style.characterProperties);
    final bytes = record.takeBytes();
    output.add([...wordU16(bytes.length), ...bytes]);
  }
  return output.takeBytes();
}
