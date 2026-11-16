import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

SfntFont aliasTestFont([String name = 'LiberationSans-Regular']) =>
    SfntFont.parse(
      File('../quds_office_editor/fonts/$name.ttf').readAsBytesSync(),
    );

// These are aliases of existing Latin outlines, not emoji/CJK coverage.
SfntFont withSharedGlyphAliases(SfntFont source) => fontWithCmap(source, {
  0x41: source.glyphIdFor(0x41),
  0x1f600: source.glyphIdFor(0x41),
  0x20000: source.glyphIdFor(0x41),
  0x5a: source.glyphIdFor(0x5a),
});

SfntFont fontWithCmap(
  SfntFont source,
  Map<int, int> mappings, {
  bool zeroAdvance = false,
}) => SfntFont(
  bytes: source.bytes,
  tables: source.tables,
  unitsPerEm: source.unitsPerEm,
  indexToLocFormat: source.indexToLocFormat,
  numGlyphs: source.numGlyphs,
  numberOfHMetrics: source.numberOfHMetrics,
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
  advanceWidths: zeroAdvance
      ? List<int>.filled(source.advanceWidths.length, 0)
      : source.advanceWidths,
  leftSideBearings: source.leftSideBearings,
  glyphOffsets: source.glyphOffsets,
  cmap: CmapTable(mappings),
  familyName: source.familyName,
);
