import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  final font = SfntFont.parse(
    File(
      '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
    ).readAsBytesSync(),
  );
  final metrics = FontMetrics(font: font, fontSizePoints: 12);

  WmlParagraph paragraph({
    int lines = 3,
    WmlLineSpacingRule rule = WmlLineSpacingRule.auto,
    double spacing = 1,
  }) => WmlParagraph(
    properties: WmlParagraphProps(
      spacingBefore: 0,
      spacingAfter: 0,
      lineSpacingRule: rule,
      lineSpacing: spacing,
    ),
    inlines: [
      WmlRun(
        text: List.generate(lines, (i) => 'Line ${i + 1}').join('\n'),
        properties: WmlRunProps(asciiFont: 'Arial', fontSizeHalfPoints: 24),
      ),
    ],
  );
  WmlDocument document(WmlParagraph p) => WmlDocument(
    sections: [
      WmlSection(
        pageSize: const WmlPageSize(width: 612, height: 792),
        margins: const WmlPageMargins(top: 72, bottom: 72, left: 72, right: 72),
        blocks: [p],
      ),
    ],
  );
  WordLayoutEngine engine() => WordLayoutEngine(
    font: null,
    measureFont: (_, size, _) => FontMetrics(font: font, fontSizePoints: size),
  );

  test('real font metrics prevent a spurious second page in 45-line text', () {
    final laid = engine().layout(document(paragraph(lines: 45)));
    expect(laid.pages, hasLength(1));
    expect(laid.pages.single.lines, hasLength(45));
    // Independently measured Arial-compatible hhea baseline pitch at 12 pt.
    expect(
      laid.pages.single.lines[1].y - laid.pages.single.lines[0].y,
      closeTo(13.798828125, 0.0001),
    );
    expect(
      laid.pages.single.lines.last.y + laid.pages.single.lines.last.height,
      lessThanOrEqualTo(720),
    );
  });

  test('exact spacing changes pitch and places surplus above baseline', () {
    final single = engine().layout(document(paragraph())).pages.single.lines;
    final exact = engine()
        .layout(
          document(paragraph(rule: WmlLineSpacingRule.exact, spacing: 18)),
        )
        .pages
        .single
        .lines;
    expect(exact[1].y - exact[0].y, 18);
    expect(
      exact[0].glyphs.first.y - single[0].glyphs.first.y,
      closeTo(18 - metrics.typographicLineHeight, 0.0001),
    );
    expect(exact[0].glyphs.first.y, greaterThan(single[0].glyphs.first.y));
  });

  test('multiple spacing changes pitch without shifting first baseline', () {
    final single = engine().layout(document(paragraph())).pages.single.lines;
    final multiple = engine()
        .layout(document(paragraph(spacing: 1.5)))
        .pages
        .single
        .lines;
    expect(multiple.first.glyphs.first.y, single.first.glyphs.first.y);
    expect(multiple[1].y - multiple[0].y, closeTo(20.6982421875, 0.0001));
  });

  test(
    'minimum spacing never shrinks natural type and aligns extra leading',
    () {
      final single = engine().layout(document(paragraph())).pages.single.lines;
      for (final minimum in [8.0, 20.0]) {
        final lines = engine()
            .layout(
              document(
                paragraph(rule: WmlLineSpacingRule.atLeast, spacing: minimum),
              ),
            )
            .pages
            .single
            .lines;
        expect(lines.first.height, greaterThanOrEqualTo(minimum));
        expect(
          lines.first.height,
          greaterThanOrEqualTo(metrics.typographicLineHeight),
        );
        expect(
          lines.first.glyphs.first.y - single.first.glyphs.first.y,
          closeTo(
            minimum > metrics.typographicLineHeight
                ? minimum - metrics.typographicLineHeight
                : 0,
            0.0001,
          ),
        );
      }
    },
  );

  test('host font metrics reach nested tall table and note story layout', () {
    final cell = paragraph(lines: 90);
    final doc = document(paragraph());
    doc.sections.first.blocks.add(
      WmlTable(
        grid: [468],
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [cell]),
            ],
          ),
        ],
      ),
    );
    WordNotes.insert(
      doc,
      doc.paragraphs.first,
      endnote: false,
      text: 'Measured note',
    );
    final seen = <String>{};
    final laid = WordLayoutEngine(
      font: null,
      measureFont: (cp, size, props) {
        seen.add(props.asciiFont);
        return FontMetrics(font: font, fontSizePoints: size);
      },
    ).layout(doc);
    final lines = laid.pages
        .expand((p) => p.lines)
        .where((l) => identical(l.sourceParagraph, cell))
        .toList();
    expect(lines, hasLength(90));
    expect(lines.first.height, closeTo(13.798828125, 0.0001));
    expect(laid.pages.expand((p) => p.notes), isNotEmpty);
    expect(seen, contains('Arial'));
  });
}
