import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  const String fontPath = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';

  test('parses DejaVu SFNT tables, metrics, outlines, and subsets', () {
    if (!File(fontPath).existsSync()) {
      markTestSkipped('DejaVuSans.ttf is not installed');
      return;
    }
    final Uint8List bytes = File(fontPath).readAsBytesSync();
    final SfntFont font = SfntFont.parse(bytes);
    expect(font.unitsPerEm, greaterThan(0));
    expect(font.numGlyphs, greaterThan(100));
    expect(font.glyphIdFor(0x41), greaterThan(0)); // A
    expect(font.advanceWidth(font.glyphIdFor(0x41)), greaterThan(0));

    final FontMetrics metrics = FontMetrics(font: font, fontSizePoints: 12);
    expect(metrics.ascender, greaterThan(0));
    expect(
      metrics.ascender,
      greaterThanOrEqualTo(font.unitsToPoints(font.winAscent, 12)),
    );
    expect(
      metrics.descender,
      lessThanOrEqualTo(font.unitsToPoints(-font.winDescent, 12)),
    );
    expect(metrics.lineHeight, greaterThan(metrics.ascender));
    expect(metrics.characterWidth(0x41), greaterThan(2));
    expect(
      metrics.measureText('AAA'),
      closeTo(metrics.characterWidth(0x41) * 3, 0.01),
    );

    final GlyphOutline outline = GlyphOutlineDecoder(
      font,
    ).decode(font.glyphIdFor(0x41));
    expect(outline.commands, isNotEmpty);
    expect(
      outline.commands.any((GlyphPathCommand c) => c.op == GlyphPathOp.move),
      isTrue,
    );

    final FontSubset subset = FontSubsetter(
      font,
    ).subset(<int>[0x20, 0x41, 0x42]);
    expect(subset.numGlyphs, lessThan(font.numGlyphs));
    expect(subset.bytes.length, lessThan(bytes.length));
    final SfntFont parsed = SfntFont.parse(subset.bytes);
    expect(parsed.glyphIdFor(0x41), greaterThan(0));
    expect(parsed.advanceWidth(parsed.glyphIdFor(0x41)), greaterThan(0));
    expect(parsed.numGlyphs, subset.numGlyphs);
  });

  test('Office typeface catalog honors run faces and Arabic theme', () {
    expect(OfficeTypeface.isArabicFamily('Noto Naskh Arabic'), isTrue);
    expect(OfficeTypeface.isThemePlaceholder('Calibri'), isTrue);
    expect(
      OfficeTypeface.paintFamily(text: 'مرحبا', runFamily: 'Calibri'),
      OfficeTypeface.arabicTheme,
    );
    expect(
      OfficeTypeface.paintFamily(text: 'مرحبا', runFamily: 'Tajawal'),
      'Tajawal',
    );
    expect(
      OfficeTypeface.paintFamily(text: 'Hello', runFamily: 'Georgia'),
      'Georgia',
    );
    final WmlDocument arabic = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              inlines: <WmlInline>[
                WmlRun(
                  text: 'تقرير',
                  properties: WmlRunProps(
                    asciiFont: 'Calibri',
                    csFont: 'Tajawal',
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    expect(OfficeTypeface.documentHasRtl(arabic), isTrue);
    expect(OfficeTypeface.preferredExportFamily(arabic), 'Tajawal');
    expect(OfficeTypeface.sizesPt, containsAll(<int>[11, 12, 24, 72]));
  });

  test('explicit complex font follows edits without changing LTR layout', () {
    final runs = [
      for (final complexScript in <bool?>[true, false, null])
        WmlRun(
          text: 'कA',
          properties: WmlRunProps(
            asciiFont: 'Liberation Serif',
            csFont: 'Noto Sans Devanagari',
            complexScript: complexScript,
          ),
        ),
    ];
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            for (final run in runs) WmlParagraph(inlines: [run]),
          ],
        ),
      ],
    );
    List<LaidOutLine> layout() =>
        WordLayoutEngine(font: null).layout(document).pages.single.lines;

    for (final complexFont in [
      'Noto Sans Devanagari',
      'Noto Serif Devanagari',
    ]) {
      runs.first.properties.csFont = complexFont;
      final lines = layout();
      expect(lines, hasLength(3));
      for (var index = 0; index < lines.length; index++) {
        final glyphs = lines[index].glyphs;
        expect(glyphs, hasLength(2));
        expect(
          glyphs.map((glyph) => glyph.fontFamily),
          everyElement(index == 0 ? complexFont : 'Liberation Serif'),
        );
        expect(glyphs.map((glyph) => glyph.glyph.level), everyElement(0));
        expect(glyphs.first.x, lessThan(glyphs.last.x));
      }
      expect(OfficeTypeface.documentHasRtl(document), isFalse);
      expect(OfficeTypeface.preferredExportFamily(document), complexFont);
    }
  });
}
