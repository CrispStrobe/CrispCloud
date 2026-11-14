// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

import 'media_word_fixture.dart';
import 'structured_word_fixture.dart';

/// False CFObj leaves ordinary text unchanged for either storage form.
Uint8List binaryObjectFalseFlagFixture({bool pieceProperty = false}) =>
    StructuredWordFixture(
      pieces: [WordFixturePiece('A\r', prm: pieceProperty ? 0x76 << 1 : 0)],
      characterRuns: [
        WordFixtureFkpRun(
          8192,
          8194,
          properties: pieceProperty ? const [] : wordSprm(0x0856, [0]),
        ),
      ],
    ).build();

/// MS-DOC 2.6.1: CFObj is Bool8, including the Prm0 isprm 0x76 form.
/// The true positive is a typed EMBED separator with CFOle2 and a referenced
/// object storage. Piece properties are applied to the separator alone.
Uint8List binaryObjectFlagFixture(int value, {bool pieceProperty = false}) {
  final original = oleWordFixture(
    characterProperties: pieceProperty ? const [] : wordSprm(0x0856, [value]),
  );
  if (!pieceProperty) return original;
  final source = BoundedCfbReader(original);
  final word = Uint8List.fromList(source.readPath('WordDocument')!);
  final table = source.readPath('1Table')!;
  final pcd = Uint8List(40);
  final data = ByteData.sublistView(pcd);
  const cps = [0, 6, 7, 10];
  const offsets = [8192, 8198, 8199];
  for (var i = 0; i < cps.length; i++) {
    data.setUint32(i * 4, cps[i], Endian.little);
  }
  for (var i = 0; i < offsets.length; i++) {
    data.setUint32(16 + i * 8 + 2, 0x40000000 | offsets[i] * 2, Endian.little);
    data.setUint16(
      16 + i * 8 + 6,
      i == 1 ? (0x76 << 1) | (value << 8) : 0,
      Endian.little,
    );
  }
  final clx = [2, ...wordU32(pcd.length), ...pcd];
  final fib = ByteData.sublistView(word);
  fib.setUint32(154 + 33 * 8, table.length, Endian.little);
  fib.setUint32(158 + 33 * 8, clx.length, Endian.little);
  final replacements = {
    'WordDocument': word,
    '1Table': Uint8List.fromList([...table, ...clx]),
  };
  final writer = CfbfWriter();
  void copy(CfbfDirectoryEntry parent, String prefix) {
    for (final entry in source.childrenOf(parent)) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isStorage) {
        writer.addStorage(
          path,
          clsid: entry.clsid,
          stateBits: entry.stateBits,
          createdFiletime: entry.createdFiletime,
          modifiedFiletime: entry.modifiedFiletime,
        );
        copy(entry, path);
      } else {
        writer.addStream(path, replacements[path] ?? source.readEntry(entry));
      }
    }
  }

  copy(source.root, '');
  return writer.build();
}

/// MS-DOC 2.6.2: fixed heading istd 1..9 overrides POutLvl, including an
/// earlier state retained by PWall before a later reset to Normal.
Uint8List binaryHeadingOutlineFixture(
  int heading,
  int outline, {
  bool historical = false,
  bool pieceProperty = false,
}) {
  assert(!historical || !pieceProperty);
  const date = 30 | (9 << 6) | (14 << 11) | (11 << 16) | (126 << 20);
  return StructuredWordFixture(
    pieces: [
      WordFixturePiece(
        'A\r',
        prm: pieceProperty ? (0x78 << 1) | (outline << 8) : 0,
      ),
    ],
    styles: {
      0: const WordFixtureStyle(name: 'Normal', builtinId: 0),
      if (heading != 0)
        heading: WordFixtureStyle(
          name: 'Heading $heading',
          builtinId: heading,
          parentIndex: 0,
        ),
    },
    paragraphRuns: [
      WordFixtureFkpRun(
        8192,
        8194,
        styleIndex: heading,
        properties: [
          if (!pieceProperty) ...wordSprm(0x2640, [outline]),
          if (historical) ...[
            ...wordSprm(0x2664, [1]),
            ...wordSprm(0x4600, wordU16(0)),
            ...wordSprm(0xc66f, [7, 1, ...wordU16(0), ...wordU32(date)]),
          ],
        ],
      ),
    ],
    extraTablePairs: {
      if (historical)
        51: [
          ...wordU16(0xffff),
          ...wordU16(1),
          ...wordU16(0),
          ...wordU16(5),
          for (final unit in 'Audit'.codeUnits) ...wordU16(unit),
        ],
    },
  ).build();
}

const binaryIndirectPositiveCases = [
  'huge-first-replaces-tail',
  'huge-nonfirst-ignored',
  'huge-nonfirst-cycle-ignored',
  'huge-minimum-size',
  'table-to-huge-chain',
];

/// Independently authored PrcData arrays. PTableProps provides a valid outer
/// PAPX containing one operation; nested arrays exercise PHugePapx ordering
/// without pretending a multi-operation GrpPrlAndIstd is a valid direct PAPX.
Uint8List binaryIndirectPropertyFixture(String name) {
  final leaf = <int>[
    ...wordSprm(0xa413, wordU16(120)),
    ...wordSprm(0xa414, wordU16(240)),
    ...wordSprm(0x2405, [1]),
  ];
  final inner = name == 'table-to-huge-chain'
      ? [...wordSprm(0x646b, wordU32(96)), ...wordSprm(0xa414, wordU16(480))]
      : leaf;
  final outer = switch (name) {
    'huge-first-replaces-tail' => [
      ...wordSprm(0x6646, wordU32(64)),
      ...wordSprm(0xa414, wordU16(480)),
    ],
    'huge-nonfirst-ignored' => [
      ...wordSprm(0xa413, wordU16(120)),
      ...wordSprm(0x6646, wordU32(0xffffff00)),
      ...wordSprm(0xa414, wordU16(240)),
    ],
    'huge-nonfirst-cycle-ignored' => [
      ...wordSprm(0xa413, wordU16(120)),
      ...wordSprm(0x6646, wordU32(0)),
      ...wordSprm(0xa414, wordU16(240)),
    ],
    'huge-minimum-size' => [
      ...wordSprm(0xa413, wordU16(120)),
      ...wordSprm(0x2405, [1]),
      ...wordSprm(0x2406, [1]),
    ],
    'huge-short-data' => [
      ...wordSprm(0x2405, [1]),
      ...wordSprm(0x2406, [1]),
      ...wordSprm(0x2407, [1]),
    ],
    'huge-first-cycle' => [
      ...wordSprm(0x6646, wordU32(0)),
      ...wordSprm(0xa414, wordU16(480)),
    ],
    'table-to-huge-chain' => [
      ...wordSprm(0x6646, wordU32(64)),
      ...wordSprm(0xa414, wordU16(480)),
    ],
    _ => throw ArgumentError.value(name),
  };
  final data = Uint8List(128);
  data.setRange(0, 2 + outer.length, [...wordU16(outer.length), ...outer]);
  data.setRange(64, 66 + inner.length, [...wordU16(inner.length), ...inner]);
  data.setRange(96, 98 + leaf.length, [...wordU16(leaf.length), ...leaf]);
  return StructuredWordFixture(
    pieces: const [WordFixturePiece('A\r')],
    paragraphRuns: [
      WordFixtureFkpRun(
        8192,
        8194,
        properties: wordSprm(
          name == 'huge-minimum-size' || name == 'huge-short-data'
              ? 0x6646
              : 0x646b,
          wordU32(0),
        ),
      ),
    ],
    extraStreams: {'Data': data},
  ).build();
}
