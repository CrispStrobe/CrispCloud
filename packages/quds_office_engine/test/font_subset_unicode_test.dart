import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/pdf/file/text/pdf_tounicode.dart';
import 'package:test/test.dart';

void main() {
  final source = SfntFont.parse(
    File(
      '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
    ).readAsBytesSync(),
  );

  // These aliases deliberately reuse Latin outlines. They test Unicode
  // transport through real font/PDF machinery, not emoji or CJK coverage.
  final unicode = _withCmap(source, {
    0x41: source.glyphIdFor(0x41),
    0x1f600: source.glyphIdFor(0x42),
    0x20000: source.glyphIdFor(0x43),
    0x10ffff: source.glyphIdFor(0x44),
    0xffff: source.glyphIdFor(0x45),
    0x5a: source.glyphIdFor(0x5a),
  });

  test('BMP subset cmap has an exact format 4 length and sentinel', () {
    final subset = FontSubsetter(source).subset('ABZ'.runes);
    final font = SfntFont.parse(subset.bytes);
    final cmap = font.tableBytes('cmap');
    final tables = _subtables(cmap);
    final table = tables.singleWhere((t) => t.format == 4);
    final data = ByteData.sublistView(cmap);
    final segments = data.getUint16(table.offset + 6) ~/ 2;
    expect(table.length, 16 + segments * 8);
    expect(table.offset + table.length, lessThanOrEqualTo(cmap.length));
    expect(data.getUint16(table.offset + 14 + (segments - 1) * 2), 0xffff);
    for (final cp in 'ABZ'.runes) {
      expect(font.glyphIdFor(cp), subset.unicodeToNewGlyph[cp]);
      expect(
        font.advanceWidth(font.glyphIdFor(cp)),
        source.advanceWidth(source.glyphIdFor(cp)),
      );
    }
  });

  test('subset preserves supplementary scalars and U+FFFF in format 12', () {
    final cps = [0x41, 0x1f600, 0x20000, 0x10ffff, 0xffff];
    final subset = FontSubsetter(unicode).subset(cps);
    final font = SfntFont.parse(subset.bytes);
    final cmap = font.tableBytes('cmap');
    final tables = _subtables(cmap);
    expect(tables.map((t) => t.format), containsAll([4, 12]));
    final full = tables.singleWhere((t) => t.format == 12);
    expect((full.platform, full.encoding), (3, 10));
    final data = ByteData.sublistView(cmap);
    expect(full.length, 16 + 12 * data.getUint32(full.offset + 12));
    expect(full.offset + full.length, cmap.length);
    for (final cp in cps) {
      final gid = font.glyphIdFor(cp);
      expect(
        gid,
        subset.unicodeToNewGlyph[cp],
        reason: 'U+${cp.toRadixString(16)}',
      );
      expect(gid, isNonZero);
      expect(
        font.advanceWidth(gid),
        unicode.advanceWidth(unicode.glyphIdFor(cp)),
      );
      expect(_outline(font, gid), _outline(unicode, unicode.glyphIdFor(cp)));
    }
  });

  test('large sparse BMP mapping never overflows format 4 length', () {
    final mappings = <int, int>{
      for (var i = 0; i < 9000; i++) 0x20 + i * 2: source.glyphIdFor(0x41),
    };
    final subset = FontSubsetter(
      _withCmap(source, mappings),
    ).subset(mappings.keys);
    final font = SfntFont.parse(subset.bytes);
    final cmap = font.tableBytes('cmap');
    final tables = _subtables(cmap);
    expect(tables.map((t) => t.format), contains(12));
    for (final table in tables) {
      expect(table.length, greaterThan(0));
      expect(table.offset + table.length, lessThanOrEqualTo(cmap.length));
      if (table.format == 4) {
        final data = ByteData.sublistView(cmap);
        expect(table.length, 16 + 4 * data.getUint16(table.offset + 6));
      }
    }
    for (final cp in mappings.keys) {
      expect(font.glyphIdFor(cp), subset.unicodeToNewGlyph[cp]);
    }
  });

  test('invalid scalar requests cannot enter generated Unicode mappings', () {
    final font = _withCmap(source, {
      0x41: source.glyphIdFor(0x41),
      -1: source.glyphIdFor(0x42),
      0xd800: source.glyphIdFor(0x43),
      0xdfff: source.glyphIdFor(0x44),
      0x110000: source.glyphIdFor(0x45),
    });
    final subset = FontSubsetter(
      font,
    ).subset([0x41, -1, 0xd800, 0xdfff, 0x110000]);
    expect(subset.unicodeToNewGlyph.keys, [0x41]);
    final parsed = SfntFont.parse(subset.bytes);
    expect(parsed.glyphIdFor(0x41), isNonZero);
    expect(parsed.glyphIdFor(0xd800), 0);
    expect(parsed.glyphIdFor(0xdfff), 0);
    expect(parsed.glyphIdFor(0x110000), 0);
  });

  test('PDF ToUnicode destinations encode supplementary UTF-16BE pairs', () {
    final cps = [0x41, 0x1f600, 0x20000, 0x10ffff];
    final subset = FontSubsetter(unicode).subset(cps);
    final cid = PdfCidFont.build(subset, unicode);
    expect(cid.toUnicodeCmap, contains('<d83dde00>'));
    expect(cid.toUnicodeCmap, contains('<d840dc00>'));
    expect(cid.toUnicodeCmap, contains('<dbffdfff>'));
    final cmap = PdfToUnicode.parse(
      Uint8List.fromList(cid.toUnicodeCmap.codeUnits),
    );
    for (final cp in cps) {
      expect(
        cmap.mapCid(subset.unicodeToNewGlyph[cp]!),
        String.fromCharCode(cp),
      );
    }
  });

  test('PDF ToUnicode does not select invalid scalar aliases', () {
    final valid = FontSubsetter(source).subset([0x41]);
    final gid = valid.unicodeToNewGlyph[0x41]!;
    final subset = FontSubset(
      bytes: valid.bytes,
      oldToNewGlyph: valid.oldToNewGlyph,
      unicodeToNewGlyph: {0x41: gid, -1: gid, 0xd800: gid, 0x110000: gid},
      numGlyphs: valid.numGlyphs,
    );
    final cid = PdfCidFont.build(subset, source);
    final cmap = PdfToUnicode.parse(
      Uint8List.fromList(cid.toUnicodeCmap.codeUnits),
    );
    expect(cmap.mapCid(gid), 'A');
  });

  test(
    'Word PDF export reopens searchable supplementary text and font cmap',
    () {
      const text = 'A\u{1f600}\u{20000}Z';
      final diagnostics = OfficeFontDiagnostics();
      final pdf = PdfFile.open(
        OfficePdfExport.word(
          WmlDocument(
            sections: [
              WmlSection(
                blocks: [
                  WmlParagraph(inlines: [WmlRun(text: text)]),
                ],
              ),
            ],
          ),
          fonts: OfficeFontSet(primary: unicode, diagnostics: diagnostics),
        ),
      );
      expect(diagnostics.missingCodePoints, isEmpty);
      expect(PdfExtract.pageText(pdf, 0), text);
      expect(
        OfficeFind.inPdf(pdf, const OfficeFindOptions(query: '\u{20000}')),
        hasLength(1),
      );
      final ops = pdf.displayList(0).ops.whereType<PdfDrawText>().toList();
      expect(ops.map((op) => op.text).join(), text);
      for (final op in ops) {
        expect(op.fontBytes, isNotNull);
        final embedded = SfntFont.parse(op.fontBytes!);
        for (final cp in op.text.runes) {
          expect(embedded.glyphIdFor(cp), isNonZero);
        }
      }
    },
  );
}

typedef _CmapSubtable = ({
  int platform,
  int encoding,
  int format,
  int offset,
  int length,
});

List<_CmapSubtable> _subtables(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return [
    for (var i = 0; i < data.getUint16(2); i++)
      (() {
        final record = 4 + i * 8;
        final offset = data.getUint32(record + 4);
        final format = data.getUint16(offset);
        return (
          platform: data.getUint16(record),
          encoding: data.getUint16(record + 2),
          format: format,
          offset: offset,
          length: format == 12
              ? data.getUint32(offset + 4)
              : data.getUint16(offset + 2),
        );
      })(),
  ];
}

Uint8List _outline(SfntFont font, int gid) => Uint8List.sublistView(
  font.tableBytes('glyf'),
  font.glyphOffsets[gid],
  font.glyphOffsets[gid + 1],
);

SfntFont _withCmap(SfntFont source, Map<int, int> mappings) => SfntFont(
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
  advanceWidths: source.advanceWidths,
  leftSideBearings: source.leftSideBearings,
  glyphOffsets: source.glyphOffsets,
  cmap: CmapTable(mappings),
  familyName: source.familyName,
);
