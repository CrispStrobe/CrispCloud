import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('table cells are laid out in columns, not stacked', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlTable(
              grid: <double>[140, 140],
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      fillColor: '1F4E79',
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: 'Left')],
                        ),
                      ],
                    ),
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: 'Right')],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages, isNotEmpty);
    final List<LaidOutLine> lines = laid.pages.first.lines;
    expect(lines.length, 2);
    expect(lines[1].x, greaterThan(lines[0].x + 40));
    expect((lines[1].y - lines[0].y).abs(), lessThan(1));
    expect(laid.pages.first.frames.length, 2);
    expect(laid.pages.first.frames.first.fillColor, '1F4E79');
    expect(laid.pages.first.frames[0].paragraphIndex, 0);
    expect(laid.pages.first.frames[1].paragraphIndex, 1);
    expect(lines[0].paragraphIndex, 0);
    expect(lines[1].paragraphIndex, 1);
  });

  test('RTL table paints the first logical column on the right', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlTable(
              grid: <double>[140, 140],
              properties: WmlTableProps(rightToLeft: true),
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: 'يمين')],
                        ),
                      ],
                    ),
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: 'يسار')],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    final List<LaidOutBox> frames = laid.pages.first.frames;
    expect(frames.length, 2);
    expect(frames[0].tableCol, 0);
    expect(frames[1].tableCol, 1);
    expect(frames[0].x, greaterThan(frames[1].x));
    final List<LaidOutLine> lines = laid.pages.first.lines;
    expect(lines[0].x, greaterThan(lines[1].x));
  });

  test('superscript and subscript shrink and shift the baseline', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              inlines: <WmlInline>[
                WmlRun(
                  text: 'H',
                  properties: WmlRunProps(fontSizeHalfPoints: 22),
                ),
                WmlRun(
                  text: '2',
                  properties: WmlRunProps(
                    fontSizeHalfPoints: 22,
                    vertAlign: WmlVertAlign.subscript,
                  ),
                ),
                WmlRun(
                  text: 'O',
                  properties: WmlRunProps(fontSizeHalfPoints: 22),
                ),
                WmlRun(
                  text: 'x',
                  properties: WmlRunProps(
                    fontSizeHalfPoints: 22,
                    vertAlign: WmlVertAlign.superscript,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final List<LaidOutGlyph> glyphs = WordLayoutEngine(font: null)
        .layout(doc)
        .pages
        .first
        .lines
        .expand((LaidOutLine line) => line.glyphs)
        .toList();
    expect(glyphs.length, 4);
    expect(glyphs[0].fontSize, 11);
    expect(glyphs[0].vertAlign, WmlVertAlign.baseline);
    expect(glyphs[1].vertAlign, WmlVertAlign.subscript);
    expect(glyphs[1].fontSize, closeTo(11 * 0.65, 0.01));
    expect(glyphs[1].y, greaterThan(glyphs[0].y));
    expect(glyphs[3].vertAlign, WmlVertAlign.superscript);
    expect(glyphs[3].fontSize, closeTo(11 * 0.65, 0.01));
    expect(glyphs[3].y, lessThan(glyphs[0].y));
  });

  test('full-page pictures paginate flush to the page', () {
    final WmlPageSize a4 = WmlPageSize.a4();
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          pageSize: a4,
          margins: const WmlPageMargins(top: 0, bottom: 0, left: 0, right: 0),
          blocks: <WmlBlock>[
            for (int i = 0; i < 3; i++)
              WmlVisual(
                visual: OfficeVisual(
                  kind: OfficeVisualKind.picture,
                  title: 'Page $i',
                  width: a4.width,
                  height: a4.height,
                ),
              ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages.length, 3);
    for (final LaidOutPage page in laid.pages) {
      expect(page.frames.length, 1);
      expect(page.frames.first.x, 0);
      expect(page.frames.first.y, 0);
      expect(page.frames.first.width, closeTo(a4.width, 0.01));
      expect(page.frames.first.height, closeTo(a4.height, 0.01));
    }
  });

  test('section columns fill left then right on the same page', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          columnCount: 2,
          columnSpace: 20,
          blocks: <WmlBlock>[
            for (int i = 0; i < 40; i++)
              WmlParagraph(
                properties: WmlParagraphProps(spacingAfter: 4),
                inlines: <WmlInline>[
                  WmlRun(
                    text: 'Column line $i with enough words to wrap a bit.',
                    properties: WmlRunProps(fontSizeHalfPoints: 22),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages, isNotEmpty);
    final LaidOutPage first = laid.pages.first;
    final double mid = first.width / 2;
    final bool hasLeft = first.lines.any((LaidOutLine line) => line.x < mid);
    final bool hasRight = first.lines.any((LaidOutLine line) => line.x > mid);
    expect(hasLeft, isTrue);
    expect(hasRight, isTrue);
  });

  test('column break moves the next paragraph to the second column', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          columnCount: 2,
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Left column')]),
            WmlParagraph(
              properties: WmlParagraphProps(columnBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'Right column')],
            ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    final List<LaidOutLine> lines = laid.pages.first.lines
        .where((LaidOutLine line) => line.sourceText == null)
        .toList();
    expect(lines.length, greaterThanOrEqualTo(2));
    expect(lines[1].x, greaterThan(lines[0].x + 40));
    expect((lines[1].y - lines[0].y).abs(), lessThan(8));
  });

  test('absolute frames do not advance the story and keep inner text', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlFrame(
              x: 80,
              y: 120,
              width: 180,
              height: 80,
              fillColor: '1F4E79',
              blocks: <WmlBlock>[
                WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Callout')]),
              ],
            ),
            WmlParagraph(
              inlines: <WmlInline>[WmlRun(text: 'Body after frame')],
            ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages.length, 1);
    final LaidOutBox frame = laid.pages.first.frames.firstWhere(
      (LaidOutBox box) => box.kind == LaidOutBoxKind.frame,
    );
    expect(frame.x, 80);
    expect(frame.y, 120);
    expect(frame.fillColor, '1F4E79');
    final LaidOutLine body = laid.pages.first.lines.last;
    expect(body.y, lessThan(100));
    expect(
      laid.pages.first.lines.any(
        (LaidOutLine line) =>
            line.glyphs.isNotEmpty && line.x >= 80 && line.y >= 120,
      ),
      isTrue,
    );
  });

  test('layout keeps global paragraph indices across sections', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'One')]),
          ],
        ),
        WmlSection(
          pageSize: const WmlPageSize(width: 400, height: 500),
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Two')]),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages.length, greaterThanOrEqualTo(2));
    expect(laid.pages.first.sectionIndex, 0);
    expect(laid.pages.last.sectionIndex, 1);
    expect(laid.pages.first.lines.first.paragraphIndex, 0);
    expect(laid.pages.last.lines.first.paragraphIndex, 1);
    expect(laid.pages.last.height, 500);
    expect(laid.pageStackTop(1, 1), greaterThan(laid.pages.first.height));
  });

  test('explicit paragraph bidi sets the layout base level', () {
    expect(WmlParagraphProps(rightToLeft: true).bidiBaseLevel, 1);
    expect(WmlParagraphProps(rightToLeft: false).bidiBaseLevel, 0);
    expect(
      WmlParagraphProps(justification: WmlJustification.right).bidiBaseLevel,
      1,
    );
    expect(WmlParagraphProps().bidiBaseLevel, isNull);

    final WmlDocument rtl = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              properties: WmlParagraphProps(
                rightToLeft: true,
                justification: WmlJustification.right,
              ),
              inlines: <WmlInline>[WmlRun(text: 'Hello')],
            ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(rtl);
    expect(laid.pages, isNotEmpty);
    expect(laid.pages.first.lines, isNotEmpty);
    expect(laid.pages.first.lines.first.justification, WmlJustification.right);
  });

  test('justified wrapped lines stretch spaces to the column edge', () {
    const String text =
        'Housing conditions in Al Tahreer are critically strained. '
        'The average household size ranges between 6 and 10 people, '
        'indicating severe overcrowding particularly within makeshift shelters '
        'and partially damaged structures across the neighbourhood.';
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              properties: WmlParagraphProps(
                justification: WmlJustification.justify,
              ),
              inlines: <WmlInline>[WmlRun(text: text)],
            ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    expect(laid.pages.first.lines.length, greaterThan(1));
    final LaidOutLine first = laid.pages.first.lines.first;
    expect(first.justification, WmlJustification.justify);
    expect(first.justificationRatio, isNot(0));
    expect(first.glyphs, isNotEmpty);
    final LaidOutGlyph last = first.glyphs.last;
    final double right = last.x + last.advance;
    expect(right, closeTo(first.x + first.width, 1.5));
    // Soft justify: never blow past the content box, and keep word gaps tame.
    expect(right, lessThanOrEqualTo(first.x + first.boxWidth + 1.5));
    final List<LaidOutGlyph> spaces = first.glyphs
        .where(
          (LaidOutGlyph g) => g.glyph.isSpace && g.glyph.codePoint != 0x09,
        )
        .toList();
    if (spaces.isNotEmpty) {
      final double em = spaces.first.fontSize;
      // Natural space + capped extra (≤0.45em), not multi-em rivers.
      for (final LaidOutGlyph space in spaces) {
        expect(space.advance, lessThanOrEqualTo(em * 1.25));
      }
    }
    expect(laid.pages.first.lines.last.justificationRatio, 0);
  });

  test('tab occupies the default half-inch stop', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'A\tB')]),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    final List<LaidOutGlyph> glyphs = laid.pages.first.lines.first.glyphs;
    expect(glyphs, hasLength(3));
    expect(glyphs[1].glyph.codePoint, 0x09);
    expect(glyphs[1].advance, closeTo(kDefaultTabWidth, 0.01));
    expect(
      glyphs[2].x,
      closeTo(glyphs[0].x + glyphs[0].advance + kDefaultTabWidth, 0.5),
    );
  });

  test('tab-only paragraph still lays out a tab glyph', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: '\t')]),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    final List<LaidOutGlyph> glyphs = laid.pages.first.lines.first.glyphs;
    expect(glyphs, hasLength(1));
    expect(glyphs.single.glyph.codePoint, 0x09);
    expect(glyphs.single.advance, closeTo(kDefaultTabWidth, 0.01));
  });

  test('long table cell text wraps inside the column', () {
    const double colW = 90;
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlTable(
              grid: <double>[colW, colW],
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[
                            WmlRun(
                              text:
                                  'نسبة المباني الصالحة والجزئية والمدمرة في الحي',
                            ),
                          ],
                        ),
                      ],
                    ),
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: '1')],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    final LaidOutBox cell = laid.pages.first.frames.first;
    final List<LaidOutLine> cellLines = laid.pages.first.lines
        .where((LaidOutLine line) => line.paragraphIndex == 0)
        .toList();
    expect(cellLines, isNotEmpty);
    expect(cellLines.length, greaterThan(1));
    for (final LaidOutLine line in cellLines) {
      expect(line.width, lessThanOrEqualTo(cell.width + 0.5));
      expect(line.x + line.width, lessThanOrEqualTo(cell.x + cell.width + 0.5));
    }
  });

  test('incremental layout reuses earlier sections', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Cover page')]),
          ],
        ),
        WmlSection(
          columnCount: 2,
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Body left')]),
            WmlParagraph(
              properties: WmlParagraphProps(columnBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'Body right')],
            ),
          ],
        ),
      ],
    );
    final WordLayoutEngine engine = WordLayoutEngine(font: null);
    final LaidOutDocument full = engine.layout(doc);
    doc.sections.last.blocks.add(
      WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'More body')]),
    );
    final LaidOutDocument incremental = engine.layout(
      doc,
      updateFields: false,
      fromSectionIndex: 1,
      reuse: full,
    );
    final LaidOutDocument again = engine.layout(doc);
    expect(incremental.pages.length, again.pages.length);
    expect(incremental.pages.first.sectionIndex, 0);
    expect(
      incremental.pages.any((LaidOutPage page) => page.sectionIndex == 1),
      isTrue,
    );
  });

  test('paragraph content box matches table cell, column, and frame origins', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          margins: const WmlPageMargins(left: 54, right: 54),
          columnCount: 2,
          columnSpace: 18,
          blocks: <WmlBlock>[
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Col A')]),
            WmlParagraph(
              properties: WmlParagraphProps(columnBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'Col B')],
            ),
          ],
        ),
        WmlSection(
          margins: const WmlPageMargins(left: 54, right: 54),
          blocks: <WmlBlock>[
            WmlTable(
              grid: <double>[160, 160],
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: 'Cell L')],
                        ),
                      ],
                    ),
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: 'Cell R')],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            WmlFrame(
              x: 122,
              y: 64,
              width: 200,
              height: 40,
              blocks: <WmlBlock>[
                WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Framed')]),
              ],
            ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    final WmlSection cols = doc.sections.first;
    final List<LaidOutLine> colLines = laid.pages
        .where((LaidOutPage page) => page.sectionIndex == 0)
        .expand((LaidOutPage page) => page.lines)
        .toList();
    expect(colLines[0].boxX, closeTo(cols.columnOriginX(0), 0.01));
    expect(colLines[0].boxWidth, closeTo(cols.columnWidth, 1));
    expect(colLines[1].boxX, closeTo(cols.columnOriginX(1), 0.01));

    final LaidOutPage tablePage = laid.pages.firstWhere(
      (LaidOutPage page) => page.sectionIndex == 1,
    );
    final List<LaidOutBox> cells = tablePage.frames
        .where((LaidOutBox box) => box.table != null)
        .toList();
    expect(cells.length, greaterThanOrEqualTo(2));
    LaidOutLine cellLineAt(LaidOutBox cell) {
      return tablePage.lines.firstWhere(
        (LaidOutLine line) =>
            (line.boxX - (cell.x + LaidOutLine.tableCellPad)).abs() < 0.5,
      );
    }

    expect(cellLineAt(cells[0]).boxX, closeTo(cells[0].x + LaidOutLine.tableCellPad, 0.01));
    expect(cellLineAt(cells[1]).boxX, closeTo(cells[1].x + LaidOutLine.tableCellPad, 0.01));
    final LaidOutLine framed = laid.pages
        .expand((LaidOutPage page) => page.lines)
        .firstWhere(
          (LaidOutLine line) =>
              (line.boxX - (122 + LaidOutLine.framePad)).abs() < 0.5,
        );
    expect(framed.boxX, closeTo(122 + LaidOutLine.framePad, 0.01));
    expect(framed.boxWidth, closeTo(200 - LaidOutLine.framePad * 2, 0.01));
  });

  test('continuous two-column section starts below a full-width heading', () {
    const WmlPageMargins margins = WmlPageMargins(
      top: 56,
      bottom: 48,
      left: 54,
      right: 54,
    );
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          margins: margins,
          blocks: <WmlBlock>[
            WmlTable(
              grid: <double>[52, 416],
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      fillColor: 'A8D69F',
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: '1.1')],
                        ),
                      ],
                    ),
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        WmlParagraph(
                          inlines: <WmlInline>[WmlRun(text: 'Heading')],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        WmlSection(
          margins: margins,
          columnCount: 2,
          columnSpace: 18,
          breakKind: WmlSectionBreakKind.continuous,
          blocks: <WmlBlock>[
            WmlParagraph(
              inlines: <WmlInline>[WmlRun(text: 'Left column body text')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(columnBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'Right column body text')],
            ),
          ],
        ),
      ],
    );
    final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
    final LaidOutPage page = laid.pages.first;
    final WmlSection cols = doc.sections[1];
    final LaidOutLine heading = page.lines.first;
    final LaidOutLine left = page.lines.firstWhere(
      (LaidOutLine line) => (line.boxX - cols.columnOriginX(0)).abs() < 1,
    );
    final LaidOutLine right = page.lines.firstWhere(
      (LaidOutLine line) => (line.boxX - cols.columnOriginX(1)).abs() < 1,
    );
    expect(left.y, greaterThan(heading.y + heading.height - 0.5));
    expect(right.y, greaterThan(heading.y + heading.height - 0.5));
    expect(right.boxX, greaterThan(left.boxX + 20));
  });
}
