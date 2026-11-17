import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  final source = _bundled('LiberationSans-Regular.ttf');

  test('short loca preserves odd-length source glyphs without truncation', () {
    final odd = _triangle(withInstruction: true);
    final even = _triangle();
    expect(odd.length.isOdd, isTrue);
    final font = _fixture(
      source,
      [Uint8List(0), odd, even],
      {0x41: 1, 0x42: 2},
    );
    final subset = FontSubsetter(font).subset('AB'.runes);
    final parsed = SfntFont.parse(subset.bytes);
    for (final cp in 'AB'.runes) {
      final original = _glyphBytes(font, font.glyphIdFor(cp));
      final retained = _glyphBytes(parsed, parsed.glyphIdFor(cp));
      expect(retained.length, greaterThanOrEqualTo(original.length));
      expect(retained.sublist(0, original.length), original);
      expect(retained.skip(original.length), everyElement(0));
      expect(_outline(parsed, cp), _outline(font, cp));
      expect(parsed.advanceWidth(parsed.glyphIdFor(cp)), 500);
    }
  });

  test('glyph alignment participates in the short-loca size decision', () {
    final padded = Uint8List(0xffff)..setAll(0, _triangle());
    final font = _fixture(
      source,
      [Uint8List(0), padded, padded],
      {0x41: 1, 0x42: 2},
    );
    final parsed = SfntFont.parse(FontSubsetter(font).subset('AB'.runes).bytes);
    expect(parsed.indexToLocFormat, 1);
    expect(parsed.glyphOffsets.last, greaterThan(0x1fffe));
    for (final cp in 'AB'.runes) {
      expect(_outline(parsed, cp), _outline(font, cp));
    }
  });

  test(
    'nested and shared composite dependencies retain remapped glyph IDs',
    () {
      final font = _fixture(
        source,
        [
          Uint8List(0),
          _triangle(),
          _triangle(), // Deliberately unused, so later IDs must change.
          _composite([1]),
          _composite([3, 1]),
        ],
        {0xc1: 4},
      );
      final subset = FontSubsetter(font).subset([0xc1]);
      expect(subset.oldToNewGlyph.keys, [0, 1, 3, 4]);
      final parsed = SfntFont.parse(subset.bytes);
      final outer = ByteData.sublistView(
        _glyphBytes(parsed, subset.oldToNewGlyph[4]!),
      );
      final inner = ByteData.sublistView(
        _glyphBytes(parsed, subset.oldToNewGlyph[3]!),
      );
      expect(outer.getUint16(12), subset.oldToNewGlyph[3]);
      expect(outer.getUint16(20), subset.oldToNewGlyph[1]);
      expect(inner.getUint16(12), subset.oldToNewGlyph[1]);
      expect(_outline(parsed, 0xc1), _outline(font, 0xc1));
    },
  );

  test(
    'composite instructions follow the last component even when flagged earlier',
    () {
      final composite = _composite([3, 1], instructionsOnFirst: true);
      final font = _fixture(
        source,
        [
          Uint8List(0),
          _triangle(),
          _triangle(),
          _composite([1]),
          composite,
        ],
        {0xc1: 4},
      );
      final subset = FontSubsetter(font).subset([0xc1]);
      final parsed = SfntFont.parse(subset.bytes);
      final actual = _glyphBytes(parsed, subset.oldToNewGlyph[4]!);
      final expected = Uint8List.fromList(composite);
      final data = ByteData.sublistView(expected);
      data.setUint16(12, subset.oldToNewGlyph[3]!);
      data.setUint16(20, subset.oldToNewGlyph[1]!);
      expect(actual.sublist(0, expected.length), expected);
      expect(actual.skip(expected.length), everyElement(0));
      expect(subset.oldToNewGlyph.keys, [0, 1, 3, 4]);
    },
  );

  test(
    'component argument and transform formats retain the complete records',
    () {
      for (final flags in [
        0x0000,
        0x0001,
        0x0002,
        0x0003,
        0x000a,
        0x0043,
        0x0082,
      ]) {
        final composite = _composite(
          [3, 1],
          componentFlags: [0x0003, flags],
          instructionsOnFirst: true,
        );
        final font = _fixture(
          source,
          [Uint8List(0), _triangle(), _triangle(), _triangle(), composite],
          {0xc1: 4},
        );
        final subset = FontSubsetter(font).subset([0xc1]);
        final parsed = SfntFont.parse(subset.bytes);
        final actual = _glyphBytes(parsed, subset.oldToNewGlyph[4]!);
        final expected = Uint8List.fromList(composite);
        final data = ByteData.sublistView(expected);
        data.setUint16(12, subset.oldToNewGlyph[3]!);
        data.setUint16(20, subset.oldToNewGlyph[1]!);
        expect(
          actual.sublist(0, expected.length),
          expected,
          reason: 'flags $flags',
        );
        expect(actual.skip(expected.length), everyElement(0));
      }
    },
  );

  test(
    'invalid requested glyph IDs and invalid cmap glyph IDs are ignored',
    () {
      final font = _fixture(
        source,
        [Uint8List(0), _triangle(), _triangle()],
        {0x41: 1, 0x42: -1, 0x43: 3, 0x44: 0xffff},
      );
      final subset = FontSubsetter(
        font,
      ).subset('ABCD'.runes, extraGlyphIds: [-1, 0, 2, 3, 0xffff]);
      expect(subset.oldToNewGlyph, {0: 0, 1: 1, 2: 2});
      expect(subset.unicodeToNewGlyph, {0x41: 1});
      final parsed = SfntFont.parse(subset.bytes);
      expect(parsed.glyphIdFor(0x41), 1);
      expect(parsed.glyphIdFor(0x42), 0);
    },
  );

  test('a dangling composite reference fails with an SFNT error', () {
    final font = _fixture(
      source,
      [
        Uint8List(0),
        _composite([2]),
      ],
      {0x41: 1},
    );
    expect(
      () => FontSubsetter(font).subset([0x41]),
      throwsA(
        isA<SfntException>().having(
          (e) => e.message,
          'message',
          contains('absent glyph'),
        ),
      ),
    );
  });

  test('composite cycles fail before recursively expanding any outlines', () {
    for (final glyphs in [
      [
        Uint8List(0),
        _composite([1]),
      ],
      [
        Uint8List(0),
        _composite([2]),
        _composite([1]),
      ],
    ]) {
      final font = _fixture(source, glyphs, {0x41: 1});
      expect(
        () => FontSubsetter(font).subset([0x41]),
        throwsA(
          isA<SfntException>().having(
            (e) => e.message,
            'message',
            contains('Cyclic'),
          ),
        ),
      );
    }
  });

  test(
    'truncated composite records and instructions fail with an SFNT error',
    () {
      final complete = _composite([2], instructionsOnFirst: true);
      for (final length in [9, 12, 17, complete.length - 1]) {
        final font = _fixture(
          source,
          [
            Uint8List(0),
            Uint8List.sublistView(complete, 0, length),
            _triangle(),
          ],
          {0x41: 1},
        );
        expect(
          () => FontSubsetter(font).subset([0x41]),
          throwsA(isA<SfntException>()),
        );
      }
    },
  );

  test(
    'truncated simple-glyph endpoints, instructions, flags and coordinates fail',
    () {
      final complete = _triangle(withInstruction: true);
      for (final length in [10, 12, 14, 15, 17, complete.length - 1]) {
        final font = _fixture(
          source,
          [Uint8List(0), Uint8List.sublistView(complete, 0, length)],
          {0x41: 1},
        );
        expect(
          () => FontSubsetter(font).subset([0x41]),
          throwsA(isA<SfntException>()),
        );
      }
      final invalidRepeat = Uint8List.fromList(_triangle());
      invalidRepeat[14] = 0x39; // A repeated zero-delta point.
      invalidRepeat[15] =
          4; // Five points do not fit the contour's three points.
      final font = _fixture(source, [Uint8List(0), invalidRepeat], {0x41: 1});
      expect(
        () => FontSubsetter(font).subset([0x41]),
        throwsA(isA<SfntException>()),
      );
    },
  );

  test('subsets preserve font-wide OS/2 metrics and embedding metadata', () {
    for (final name in [
      'LiberationSans-Regular.ttf',
      'LiberationMono-BoldItalic.ttf',
      'NotoNaskhArabic-Regular.ttf',
    ]) {
      final font = _bundled(name);
      final subset = FontSubsetter(font).subset('AB\u0627\u0628'.runes);
      final parsed = SfntFont.parse(subset.bytes);
      final before = font.tableBytes('OS/2');
      final after = parsed.tableBytes('OS/2');
      expect(after, hasLength(before.length));
      for (var i = 0; i < before.length; i++) {
        if ((i >= 42 && i < 58) || (i >= 64 && i < 68) || (i >= 78 && i < 86)) {
          continue; // Cmap-dependent coverage fields are deliberately updated.
        }
        expect(after[i], before[i], reason: '$name byte $i');
      }
      expect(parsed.capHeight, font.capHeight, reason: name);
      expect(parsed.winAscent, font.winAscent, reason: name);
      expect(parsed.winDescent, font.winDescent, reason: name);
      expect(parsed.ascender, font.ascender, reason: name);
      expect(parsed.descender, font.descender, reason: name);
      expect(parsed.lineGap, font.lineGap, reason: name);
    }
  });

  test(
    'OS/2 repertoire metadata describes the subset instead of the source face',
    () {
      final parsed = SfntFont.parse(
        FontSubsetter(source).subset('AB'.runes).bytes,
      );
      final data = ByteData.sublistView(parsed.tableBytes('OS/2'));
      expect(data.getUint16(64), 0x41);
      expect(data.getUint16(66), 0x42);
      expect(
        [for (var i = 0; i < 4; i++) data.getUint32(42 + 4 * i)],
        [1, 0, 0, 0],
      );
      expect(data.getUint32(78), 0);
      expect(data.getUint32(82), 0);

      final aliased = _fixture(
        source,
        [Uint8List(0), _triangle(), _triangle()],
        {0x1f600: 1, 0x20000: 2},
      );
      final supplementary = SfntFont.parse(
        FontSubsetter(aliased).subset([0x1f600, 0x20000]).bytes,
      );
      final full = ByteData.sublistView(supplementary.tableBytes('OS/2'));
      expect(full.getUint16(64), 0xffff);
      expect(full.getUint16(66), 0xffff);
      // Non-Plane 0 (57) and CJK unified ideographs (59, including Extension B).
      expect(full.getUint32(46), (1 << 25) | (1 << 27));
      expect(full.getUint32(42), 0);
      expect(full.getUint32(50), 0);
      expect(full.getUint32(54), 0);
    },
  );

  test('an empty subset clears coverage without changing embedding rights', () {
    final table = Uint8List.fromList(source.tableBytes('OS/2'));
    ByteData.sublistView(table).setUint16(8, 0x0008); // Editable embedding.
    final font = _withTables(source, {'OS/2': table});
    final parsed = SfntFont.parse(FontSubsetter(font).subset([]).bytes);
    final data = ByteData.sublistView(parsed.tableBytes('OS/2'));
    expect(data.getUint16(8), 0x0008);
    expect(data.getUint16(64), 0);
    expect(data.getUint16(66), 0);
    expect(
      [for (var i = 0; i < 4; i++) data.getUint32(42 + 4 * i)],
      [0, 0, 0, 0],
    );
    expect(data.getUint32(78), 0);
    expect(data.getUint32(82), 0);
  });

  test(
    'post v3 preserves style metrics without stale names or memory estimates',
    () {
      final font = _bundled('LiberationMono-BoldItalic.ttf');
      final original = Uint8List.fromList(font.tableBytes('post'));
      final data = ByteData.sublistView(original);
      expect(data.getUint32(0), 0x00020000);
      expect(data.getInt32(4), isNegative);
      expect(data.getUint32(12), isNonZero);
      for (var offset = 16; offset < 32; offset += 4) {
        data.setUint32(offset, 12345);
      }
      final modified = _withTables(font, {'post': original});
      final parsed = SfntFont.parse(
        FontSubsetter(modified).subset('AB'.runes).bytes,
      );
      final post = parsed.tableBytes('post');
      expect(post, hasLength(32));
      expect(ByteData.sublistView(post).getUint32(0), 0x00030000);
      expect(post.sublist(4, 16), original.sublist(4, 16));
      expect(post.sublist(16), everyElement(0));
      expect(parsed.numGlyphs, lessThan(font.numGlyphs));
    },
  );

  test('retained font metadata does not alter source buffers', () {
    final before = Uint8List.fromList(source.bytes);
    final parsed = SfntFont.parse(
      FontSubsetter(source).subset('AB'.runes).bytes,
    );
    parsed.tableBytes('OS/2').fillRange(0, parsed.tableBytes('OS/2').length, 0);
    parsed.tableBytes('post').fillRange(0, parsed.tableBytes('post').length, 0);
    expect(source.bytes, before);
  });
}

SfntFont _bundled(String filename) => SfntFont.parse(
  File('../quds_office_editor/fonts/$filename').readAsBytesSync(),
);

Uint8List _triangle({bool withInstruction = false}) => Uint8List.fromList([
  0, 1, // One contour.
  0, 0, 0, 0, 0, 100, 0, 100, // Bounding box.
  0, 2, // Three points.
  0, withInstruction ? 1 : 0,
  if (withInstruction) 0x00, // SVTCA[y]; makes the valid glyph length odd.
  0x31, 0x33, 0x27, // On-curve flags for (0,0), (100,0), (0,100).
  100, 100, 100, // Compact x/y deltas.
]);

Uint8List _composite(
  List<int> children, {
  bool instructionsOnFirst = false,
  List<int>? componentFlags,
}) {
  final bytes = BytesBuilder()..add([0xff, 0xff, 0, 0, 0, 0, 0, 100, 0, 100]);
  for (var i = 0; i < children.length; i++) {
    final flags =
        (componentFlags?[i] ?? 0x0003) |
        (i < children.length - 1 ? 0x0020 : 0) |
        (i == 0 && instructionsOnFirst ? 0x0100 : 0);
    bytes.add([
      flags >> 8,
      flags & 0xff,
      children[i] >> 8,
      children[i] & 0xff,
      0,
      0,
    ]);
    if ((flags & 0x0001) != 0) bytes.add([0, 0]);
    if ((flags & 0x0008) != 0) {
      bytes.add([0x40, 0]);
    } else if ((flags & 0x0040) != 0) {
      bytes.add([0x40, 0, 0x40, 0]);
    } else if ((flags & 0x0080) != 0) {
      bytes.add([0x40, 0, 0, 0, 0, 0, 0x40, 0]);
    }
  }
  if (instructionsOnFirst) bytes.add([0, 1, 0x00]);
  return bytes.takeBytes();
}

// Build parsed-font fixtures directly. This permits exact glyph storage and
// malformed dependency cases without adding another font asset or platform
// dependency. Font-wide tables come from the required bundled font.
SfntFont _fixture(SfntFont source, List<Uint8List> glyphs, Map<int, int> cmap) {
  final bytes = BytesBuilder();
  final offsets = [0];
  for (final glyph in glyphs) {
    bytes.add(glyph);
    offsets.add(bytes.length);
  }
  return _withTables(
    source,
    {'glyf': bytes.takeBytes()},
    glyphCount: glyphs.length,
    glyphOffsets: offsets,
    cmap: CmapTable(cmap),
  );
}

SfntFont _withTables(
  SfntFont source,
  Map<String, Uint8List> replacements, {
  int? glyphCount,
  List<int>? glyphOffsets,
  CmapTable? cmap,
}) {
  final storage = BytesBuilder();
  final tables = <String, SfntTableRecord>{};
  for (final tag in source.tables.keys) {
    final table = replacements[tag] ?? source.tableBytes(tag);
    tables[tag] = SfntTableRecord(
      tag: tag,
      checksum: 0,
      offset: storage.length,
      length: table.length,
    );
    storage.add(table);
  }
  return SfntFont(
    bytes: storage.takeBytes(),
    tables: tables,
    unitsPerEm: source.unitsPerEm,
    indexToLocFormat: glyphOffsets == null ? source.indexToLocFormat : 1,
    numGlyphs: glyphCount ?? source.numGlyphs,
    numberOfHMetrics: glyphCount ?? source.numberOfHMetrics,
    ascender: source.ascender,
    descender: source.descender,
    lineGap: source.lineGap,
    capHeight: source.capHeight,
    winAscent: source.winAscent,
    winDescent: source.winDescent,
    xMin: source.xMin,
    yMin: source.yMin,
    xMax: source.xMax,
    yMax: source.yMax,
    advanceWidths: glyphCount == null
        ? source.advanceWidths
        : List.filled(glyphCount, 500),
    leftSideBearings: glyphCount == null
        ? source.leftSideBearings
        : List.filled(glyphCount, 0),
    glyphOffsets: glyphOffsets ?? source.glyphOffsets,
    cmap: cmap ?? source.cmap,
    familyName: source.familyName,
  );
}

Uint8List _glyphBytes(SfntFont font, int gid) => Uint8List.sublistView(
  font.tableBytes('glyf'),
  font.glyphOffsets[gid],
  font.glyphOffsets[gid + 1],
);

List<List<Object>> _outline(SfntFont font, int cp) => [
  for (final command in GlyphOutlineDecoder(
    font,
  ).decode(font.glyphIdFor(cp)).commands)
    [command.op, command.x, command.y, command.cx, command.cy],
];
