import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

SfntFont _fontWithGlyf(Uint8List glyf) {
  const offset = 12;
  final bytes = Uint8List(offset + glyf.length)
    ..setRange(offset, offset + glyf.length, glyf);
  return SfntFont(
    bytes: bytes,
    tables: <String, SfntTableRecord>{
      'glyf': SfntTableRecord(
        tag: 'glyf',
        checksum: 0,
        offset: offset,
        length: glyf.length,
      ),
    },
    unitsPerEm: 1000,
    indexToLocFormat: 0,
    numGlyphs: 1,
    numberOfHMetrics: 1,
    ascender: 800,
    descender: -200,
    lineGap: 0,
    capHeight: 700,
    winAscent: 800,
    winDescent: 200,
    xMin: 0,
    yMin: -200,
    xMax: 1000,
    yMax: 800,
    advanceWidths: const <int>[500],
    leftSideBearings: const <int>[0],
    glyphOffsets: <int>[offset, offset + glyf.length],
    cmap: CmapTable(const <int, int>{0: 0}),
  );
}

void main() {
  test(
    'hostile contour table yields an empty outline instead of RangeError',
    () {
      // One contour ending at point 100, but no instruction length, flags or
      // coordinates follow. The cursor used to seek past the glyph buffer.
      final glyf = Uint8List.fromList(<int>[
        0, 1, // numberOfContours
        0, 0, 0, 0, 0, 0, 0, 0, // bbox
        0, 100, // endPtsOfContours
      ]);
      final outline = GlyphOutlineDecoder(_fontWithGlyf(glyf)).decode(0);
      expect(outline.commands, isEmpty);
      expect(outline.componentGlyphIds, isEmpty);
    },
  );

  test('non-monotonic contour endpoints are rejected before allocation', () {
    final glyf = Uint8List.fromList(<int>[
      0, 2, // numberOfContours
      0, 0, 0, 0, 0, 0, 0, 0, // bbox
      0, 5, // first contour
      0, 2, // second contour points backwards
      0, 0, // instruction length
    ]);
    final outline = GlyphOutlineDecoder(_fontWithGlyf(glyf)).decode(0);
    expect(outline.commands, isEmpty);
  });

  test('repeat flags cannot grow a glyph beyond its point budget', () {
    final glyf = Uint8List.fromList(<int>[
      0, 1, // numberOfContours
      0, 0, 0, 0, 0, 0, 0, 0, // bbox
      0, 1, // one point
      0, 0, // instruction length
      0x09, 255, // repeat flag advertises 256 extra points
    ]);
    final outline = GlyphOutlineDecoder(_fontWithGlyf(glyf)).decode(0);
    expect(outline.commands, isEmpty);
  });
}
