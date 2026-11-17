import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('cmap selection', () {
    test('Unicode mappings take precedence over a denser legacy table', () {
      final table = _parse([
        (platform: 3, encoding: 1, bytes: _format4([(0x41, 0x41, -58)])),
        (
          platform: 1,
          encoding: 0,
          bytes: _format0({0x41: 9, 0x42: 10, 0x43: 11}),
        ),
      ]);
      expect(table.glyphId(0x41), 7);
      expect(table.glyphId(0x42), 0);
    });

    test('full Unicode table is authoritative even if BMP has more hits', () {
      final table = _parse([
        (
          platform: 0,
          encoding: 4,
          bytes: _format12([(0x41, 0x41, 7), (0x1f600, 0x1f600, 8)]),
        ),
        (platform: 3, encoding: 1, bytes: _format4([(0x41, 0x43, -62)])),
      ]);
      expect(table.glyphId(0x41), 7);
      expect(table.glyphId(0x1f600), 8);
      expect(table.glyphId(0x43), 0);
    });

    test('empty Unicode coverage cannot be replaced by legacy byte codes', () {
      final table = _parse([
        (platform: 3, encoding: 1, bytes: _format4([])),
        (platform: 1, encoding: 0, bytes: _format0({0x41: 9})),
      ]);
      expect(table.glyphId(0x41), 0);
    });

    test('legacy format 0 remains available when Unicode is unavailable', () {
      final table = _parse([
        (platform: 0, encoding: 5, bytes: Uint8List.fromList([0, 14])),
        (platform: 1, encoding: 0, bytes: _format0({0x41: 7})),
      ]);
      expect(table.glyphId(0x41), 7);
      expect(table.glyphId(0x42), 0);
    });

    test(
      'Windows Symbol fallback preserves symbol keys ahead of Mac bytes',
      () {
        final table = _parse([
          (
            platform: 3,
            encoding: 0,
            bytes: _format4([(0xf041, 0xf041, 7 - 0xf041)]),
          ),
          (platform: 1, encoding: 0, bytes: _format0({0x41: 9, 0x42: 10})),
        ]);
        expect(table.glyphId(0xf041), 7);
        expect(table.glyphId(0x41), 0);
      },
    );

    test('legacy Big5 byte pairs are not mistaken for Unicode surrogates', () {
      final table = _parse([
        (
          platform: 3,
          encoding: 4,
          bytes: _format4([(0xd840, 0xd840, 1 - 0xd840)]),
        ),
      ]);
      expect(table.glyphId(0xd840), 1);
    });

    test('unselected legacy subtable bodies do not affect Unicode parsing', () {
      final table = _parse([
        (platform: 3, encoding: 1, bytes: _format4([(0x41, 0x41, -58)])),
        (platform: 1, encoding: 0, bytes: _set16(_format0({0x41: 9}), 2, 6)),
      ]);
      expect(table.glyphId(0x41), 7);
    });
  });

  group('valid cmap mappings', () {
    test('format 4 applies deltas only to nonzero glyph-array entries', () {
      final table = _parseOne(
        _format4([(0x41, 0x43, 2)], glyphArray: [1, 0, 2]),
      );
      expect(table.glyphId(0x41), 3);
      expect(table.glyphId(0x42), 0);
      expect(table.glyphId(0x43), 4);
      expect(table.glyphId(0xffff), 0);
    });

    test('format 4 missing-glyph surrogate entries are not exposed', () {
      final table = _parseOne(_format4([(0xd800, 0xd800, 0x2800)]));
      expect(table.glyphId(0xd800), 0);
      expect(table.mappings.map((entry) => entry.key), isNot(contains(0xd800)));
    });

    test(
      'format 12 preserves gaps, aliases, supplementary and final scalars',
      () {
        final table = _parseOne(
          _format12([
            (0x41, 0x43, 1),
            (0x1f600, 0x1f601, 1),
            (0x10ffff, 0x10ffff, 3),
          ]),
        );
        expect(table.glyphId(0x40), 0);
        expect(table.glyphId(0x41), 1);
        expect(table.glyphId(0x43), 3);
        expect(table.glyphId(0x44), 0);
        expect(table.glyphId(0x1f600), 1);
        expect(table.glyphId(0x1f601), 2);
        expect(table.glyphId(0x10ffff), 3);
        expect(table.glyphId(0x110000), 0);
        expect(Map<int, int>.fromEntries(table.mappings), {
          0: 0,
          0x41: 1,
          0x42: 2,
          0x43: 3,
          0x1f600: 1,
          0x1f601: 2,
          0x10ffff: 3,
        });
      },
    );

    test('bundled fonts and new subsets retain valid glyph identities', () {
      for (final name in [
        'LiberationSans-Regular.ttf',
        'NotoNaskhArabic-Regular.ttf',
      ]) {
        final bytes = File(
          '../quds_office_editor/fonts/$name',
        ).readAsBytesSync();
        final font = SfntFont.parse(bytes);
        expect(font.cmap.mappings, isNotEmpty);
        for (final mapping in font.cmap.mappings) {
          expect(mapping.value, inInclusiveRange(0, font.numGlyphs - 1));
        }
        final scalars = font.cmap.mappings
            .where((entry) => entry.value != 0)
            .take(12)
            .map((entry) => entry.key)
            .toList();
        final subset = FontSubsetter(font).subset(scalars);
        final reopened = SfntFont.parse(subset.bytes);
        for (final scalar in scalars) {
          expect(reopened.glyphIdFor(scalar), subset.unicodeToNewGlyph[scalar]);
        }
      }
    });
  });

  group('format 4 rejects malformed bounds and mappings', () {
    final cases = <String, Uint8List>{
      'short declared length cannot consume adjacent bytes': _set16(
        _format4([(0x41, 0x41, -64)]),
        2,
        24,
      ),
      'declared length exceeds available bytes': _set16(
        _format4([(0x41, 0x41, -64)]),
        2,
        64,
      ),
      'odd segment count': _set16(_format4([(0x41, 0x41, -64)]), 6, 5),
      'zero segment count': _set16(_format4([]), 6, 0),
      'truncated segment arrays': Uint8List.sublistView(
        _format4([(0x41, 0x41, -64)]),
        0,
        20,
      ),
      'reversed segment': _format4([(0x42, 0x41, -64)]),
      'overlapping segments': _format4([(0x41, 0x42, -64), (0x42, 0x43, -63)]),
      'unsorted segments': _format4([(0x42, 0x43, -64), (0x41, 0x41, -63)]),
      'missing terminal segment': _set16(
        _set16(_format4([(0x41, 0x41, -64)]), 16, 0x42),
        22,
        0x42,
      ),
      'glyph pointer into segment arrays': _set16(
        _format4([(0x41, 0x41, 0)], glyphArray: [1]),
        28,
        2,
      ),
      'unaligned glyph pointer': _set16(
        _format4([(0x41, 0x41, 0)], glyphArray: [1, 2]),
        28,
        5,
      ),
      'glyph pointer outside declared length': _set16(
        _format4([(0x41, 0x41, 0)], glyphArray: [1]),
        28,
        8,
      ),
      'surrogate maps to a glyph': _format4([(0xd800, 0xd800, 0x2801)]),
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(() => _parseOne(entry.value), throwsA(isA<SfntException>()));
      });
    }
  });

  group('format 12 rejects malformed ranges before expansion', () {
    // All ranges used by the pre-fix regression run have at most three codes.
    // Even invalid uint32 endpoints therefore cannot trigger a large loop.
    final cases = <String, Uint8List>{
      'short declared length cannot consume adjacent groups': _set32(
        _format12([(0x41, 0x41, 1)]),
        4,
        16,
      ),
      'declared length exceeds available bytes': _set32(
        _format12([(0x41, 0x41, 1)]),
        4,
        40,
      ),
      'truncated group': Uint8List.sublistView(
        _format12([(0x41, 0x41, 1)]),
        0,
        24,
      ),
      'unbounded group count without group data': _set32(
        _format12([]),
        12,
        0xffffffff,
      ),
      'reversed range': _format12([(0x42, 0x41, 1)]),
      'overlapping groups': _format12([(0x41, 0x42, 1), (0x42, 0x43, 4)]),
      'unsorted groups': _format12([(0x42, 0x42, 1), (0x41, 0x41, 4)]),
      'code points beyond Unicode': _format12([(0x110000, 0x110001, 1)]),
      'uint32 endpoints beyond Unicode': _format12([
        (0xfffffffe, 0xffffffff, 1),
      ]),
      'surrogate range': _format12([(0xd800, 0xd801, 1)]),
      'range crossing into surrogates': _format12([(0xd7ff, 0xd800, 1)]),
      'glyph start beyond uint16': _format12([(0x41, 0x41, 0x10000)]),
      'glyph end beyond uint16': _format12([(0x41, 0x42, 0xffff)]),
      'nonzero reserved field': _set16(_format12([(0x41, 0x41, 1)]), 2, 1),
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(() => _parseOne(entry.value), throwsA(isA<SfntException>()));
      });
    }
  });

  group('format 0 and directory validation', () {
    test('format 0 must include its declared 256-byte array', () {
      expect(
        () => _parseOne(_set16(_format0({0x41: 1}), 2, 6)),
        throwsA(isA<SfntException>()),
      );
      expect(
        () => _parseOne(Uint8List.sublistView(_format0({0x41: 1}), 0, 261)),
        throwsA(isA<SfntException>()),
      );
    });

    test(
      'compact format 12 supports the scalar space without eager expansion',
      () {
        final groups = <(int, int, int)>[(0, 0xd7ff, 0)];
        for (var start = 0xe000; start <= 0x10ffff; start += 0x10000) {
          final end = start + 0xffff > 0x10ffff ? 0x10ffff : start + 0xffff;
          groups.add((start, end, 0));
        }
        final bytes = _format12(groups);
        expect(bytes.length, lessThan(300));
        final table = _parseOne(bytes);
        // The parser owns the validated groups; later mutation of input bytes
        // cannot alter the range checks or change a lookup into a numeric loop.
        bytes.fillRange(0, bytes.length, 0xff);
        for (final group in groups) {
          expect(table.glyphId(group.$1), 0);
          expect(table.glyphId(group.$2), group.$2 - group.$1);
        }
        expect(table.glyphId(0xd800), 0);
        expect(table.glyphId(0xdfff), 0);
        expect(table.glyphId(0x110000), 0);
        expect(Map<int, int>.fromEntries(table.mappings.take(3)), {
          0: 0,
          1: 1,
          2: 2,
        });
      },
    );

    test('format 12 rejects a uint32-sized range before numeric iteration', () {
      // This probe was introduced only after validating the small pre-fix
      // regressions. The hostile input is a single 28-byte subtable.
      expect(
        () => _parseOne(_format12([(0, 0xffffffff, 0)])),
        throwsA(isA<SfntException>()),
      );
    });

    test('cmap subtable offsets are relative to the cursor table start', () {
      final bytes = Uint8List.fromList([
        1,
        2,
        3,
        4,
        ..._cmap([
          (platform: 3, encoding: 10, bytes: _format12([(0x41, 0x41, 7)])),
        ]),
      ]);
      final table = CmapTable.parse(ByteCursor(bytes, offset: 4));
      expect(table.glyphId(0x41), 7);
    });

    test('cmap version and encoding array are validated', () {
      expect(
        () => CmapTable.parse(ByteCursor(_set16(_cmap([]), 0, 1))),
        throwsA(isA<SfntException>()),
      );
      expect(
        () => CmapTable.parse(ByteCursor(_set16(_cmap([]), 2, 1))),
        throwsA(isA<SfntException>()),
      );
    });

    for (final offset in [4, 0xffffffff]) {
      test(
        'encoding offset $offset cannot escape or overlap its directory',
        () {
          final bytes = _cmap([
            (platform: 3, encoding: 1, bytes: _format4([(0x41, 0x41, -64)])),
          ]);
          expect(
            () => CmapTable.parse(ByteCursor(_set32(bytes, 8, offset))),
            throwsA(isA<SfntException>()),
          );
        },
      );
    }

    test('truncated SFNT directory reports a typed font error', () {
      final bytes = Uint8List(12);
      ByteData.sublistView(bytes).setUint16(4, 1);
      expect(() => SfntFont.parse(bytes), throwsA(isA<SfntException>()));
    });

    test('SFNT table extent must remain inside the font', () {
      final bytes = _font(_format4([(0x41, 0x41, -64)]));
      expect(
        () => SfntFont.parse(_set32(bytes, 20, 0xffffffff)),
        throwsA(isA<SfntException>()),
      );
      expect(
        () => SfntFont.parse(_set32(bytes, 24, 0xffffffff)),
        throwsA(isA<SfntException>()),
      );
    });

    test('truncated required tables report typed font errors', () {
      final bytes = _font(_format4([(0x41, 0x41, -64)]));
      expect(
        () => SfntFont.parse(_set32(bytes, 24, 2)),
        throwsA(isA<SfntException>()),
      );
    });

    test('duplicate SFNT table tags are rejected before table parsing', () {
      final bytes = _font(_format4([(0x41, 0x41, -64)]));
      bytes.setRange(28, 32, 'head'.codeUnits);
      expect(
        () => SfntFont.parse(bytes),
        throwsA(
          isA<SfntException>().having(
            (error) => error.message,
            'message',
            contains('Duplicate'),
          ),
        ),
      );
    });
  });

  group('cmap glyph IDs must exist in maxp', () {
    test('invalid explicit glyph counts are rejected', () {
      for (final count in [-1, 0, 0x10001]) {
        expect(
          () => CmapTable.parse(ByteCursor(_cmap([])), numGlyphs: count),
          throwsA(isA<SfntException>()),
        );
      }
    });
    for (final entry in <String, Uint8List>{
      'format 0': _format0({0x41: 2}),
      'format 4 delta': _format4([(0x41, 0x41, -63)]),
      'format 4 glyph array': _format4([(0x41, 0x41, 0)], glyphArray: [2]),
      'format 12 start': _format12([(0x41, 0x41, 2)]),
      'format 12 end': _format12([(0x41, 0x42, 1)]),
    }.entries) {
      test(entry.key, () {
        expect(
          () => SfntFont.parse(_font(entry.value, numGlyphs: 2)),
          throwsA(isA<SfntException>()),
        );
      });
    }
  });
}

typedef _Encoding = ({int platform, int encoding, Uint8List bytes});

CmapTable _parse(List<_Encoding> records) =>
    CmapTable.parse(ByteCursor(_cmap(records)));

CmapTable _parseOne(Uint8List bytes) =>
    _parse([(platform: 3, encoding: bytes[1] == 12 ? 10 : 1, bytes: bytes)]);

Uint8List _cmap(List<_Encoding> records) {
  final out = ByteSink()
    ..u16be(0)
    ..u16be(records.length);
  var offset = 4 + 8 * records.length;
  for (final record in records) {
    out
      ..u16be(record.platform)
      ..u16be(record.encoding)
      ..u32be(offset);
    offset += record.bytes.length;
  }
  for (final record in records) {
    out.add(record.bytes);
  }
  return out.takeBytes();
}

Uint8List _format0(Map<int, int> mappings) {
  final out = ByteSink()
    ..u16be(0)
    ..u16be(262)
    ..u16be(0);
  for (var code = 0; code < 256; code++) {
    out.u8(mappings[code] ?? 0);
  }
  return out.takeBytes();
}

Uint8List _format4(List<(int, int, int)> segments, {List<int>? glyphArray}) {
  final all = [...segments, (0xffff, 0xffff, 1)];
  final out = ByteSink()
    ..u16be(4)
    ..u16be(16 + 8 * all.length + 2 * (glyphArray?.length ?? 0))
    ..u16be(0)
    ..u16be(2 * all.length)
    ..u16be(0)
    ..u16be(0)
    ..u16be(0);
  for (final segment in all) {
    out.u16be(segment.$2);
  }
  out.u16be(0);
  for (final segment in all) {
    out.u16be(segment.$1);
  }
  for (final segment in all) {
    out.u16be(segment.$3);
  }
  for (var i = 0; i < all.length; i++) {
    out.u16be(i == 0 && glyphArray != null ? 2 * all.length : 0);
  }
  for (final glyph in glyphArray ?? <int>[]) {
    out.u16be(glyph);
  }
  return out.takeBytes();
}

Uint8List _format12(List<(int, int, int)> groups) {
  final out = ByteSink()
    ..u16be(12)
    ..u16be(0)
    ..u32be(16 + 12 * groups.length)
    ..u32be(0)
    ..u32be(groups.length);
  for (final group in groups) {
    out
      ..u32be(group.$1)
      ..u32be(group.$2)
      ..u32be(group.$3);
  }
  return out.takeBytes();
}

Uint8List _font(Uint8List subtable, {int numGlyphs = 4}) {
  final head = Uint8List(54);
  ByteData.sublistView(head).setUint16(18, 1000);
  final hhea = Uint8List(36);
  ByteData.sublistView(hhea).setUint16(34, numGlyphs);
  final maxp = Uint8List(6);
  ByteData.sublistView(maxp).setUint16(4, numGlyphs);
  final tables = <String, Uint8List>{
    'head': head,
    'hhea': hhea,
    'maxp': maxp,
    'hmtx': Uint8List(4 * numGlyphs),
    'cmap': _cmap([
      (platform: 3, encoding: subtable[1] == 12 ? 10 : 1, bytes: subtable),
    ]),
  };
  final out = ByteSink()
    ..u32be(0x10000)
    ..u16be(tables.length)
    ..u16be(0)
    ..u16be(0)
    ..u16be(0);
  var offset = 12 + 16 * tables.length;
  for (final entry in tables.entries) {
    out
      ..add(entry.key.codeUnits)
      ..u32be(0)
      ..u32be(offset)
      ..u32be(entry.value.length);
    offset += entry.value.length;
  }
  for (final bytes in tables.values) {
    out.add(bytes);
  }
  return out.takeBytes();
}

Uint8List _set16(Uint8List bytes, int offset, int value) {
  final copy = Uint8List.fromList(bytes);
  ByteData.sublistView(copy).setUint16(offset, value);
  return copy;
}

Uint8List _set32(Uint8List bytes, int offset, int value) {
  final copy = Uint8List.fromList(bytes);
  ByteData.sublistView(copy).setUint32(offset, value);
  return copy;
}
