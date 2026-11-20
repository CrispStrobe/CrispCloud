import 'dart:convert';
import 'dart:math';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Independent geometry comparison: this deliberately does not call the new
// production fingerprint helper. Every edit is checked against a fresh engine.
List<Object?> _line(LaidOutLine line) => <Object?>[
  line.x,
  line.y,
  line.width,
  line.height,
  line.pageIndex,
  line.paragraphIndex,
  line.justification.name,
  line.justificationRatio,
  line.boxX,
  line.boxWidth,
  line.listLabel,
  line.listMarkerX,
  line.isParagraphStart,
  line.isFooter,
  line.sourceText,
  line.sourceParagraph?.text,
  line.proofingOffsets,
  line.tocTargetParagraph,
  line.tocLeader,
  line.overlayText,
  line.overlayColor,
  line.overlaySize,
  line.overlayBold,
  for (final glyph in line.glyphs)
    <Object?>[
      glyph.glyph.codePoint,
      glyph.glyph.glyphId,
      glyph.glyph.logicalIndex,
      glyph.glyph.level,
      glyph.x,
      glyph.y,
      glyph.advance,
      glyph.paintDx,
      glyph.paintDy,
      glyph.logicalEnd,
      glyph.color,
      glyph.fontSize,
      glyph.fontFamily,
      glyph.bold,
      glyph.italic,
      glyph.underline.name,
      glyph.kerning,
      glyph.strike,
      glyph.highlight,
      glyph.vertAlign.name,
      glyph.displayText,
      glyph.displayOffset,
      glyph.sourceEnd,
      glyph.actualText,
      glyph.commentIds,
      glyph.hyperlink?.url,
      glyph.hyperlink?.anchor,
    ],
];

String _geometry(LaidOutDocument layout) => jsonEncode(<Object?>[
  layout.pageSize.width,
  layout.pageSize.height,
  for (final page in layout.pages)
    <Object?>[
      page.index,
      page.sectionIndex,
      page.width,
      page.height,
      page.headerBand.top,
      page.headerBand.height,
      page.footerBand.top,
      page.footerBand.height,
      page.lines.map(_line).toList(),
      page.header.map(_line).toList(),
      page.footer.map(_line).toList(),
      page.notes.map(_line).toList(),
      for (final box in page.frames)
        <Object?>[
          box.kind.name,
          box.x,
          box.y,
          box.width,
          box.height,
          box.paragraphIndex,
          box.paragraphEnd,
          box.tableRow,
          box.tableCol,
          box.tableGridCol,
          box.fillColor,
          box.strokeColor,
          box.strokeWidth,
          box.strokeTop,
          box.strokeBottom,
          box.strokeLeft,
          box.strokeRight,
          box.isNoteContent,
          box.visual?.kind.name,
          box.visual?.title,
          box.visual?.width,
          box.visual?.height,
        ],
    ],
]);

void _equivalent(WmlDocument document, LaidOutDocument actual, String label) {
  final observed = _geometry(actual);
  final expected = _geometry(
    WordLayoutEngine(font: null).layout(document, updateFields: false),
  );
  if (observed == expected) return;
  var offset = 0;
  while (offset < min(observed.length, expected.length) &&
      observed.codeUnitAt(offset) == expected.codeUnitAt(offset)) {
    offset++;
  }
  final begin = max(0, offset - 120);
  fail(
    '$label: incremental/full geometry differs at character $offset\n'
    'actual: ${observed.substring(begin, min(observed.length, offset + 240))}\n'
    'fresh:  ${expected.substring(begin, min(expected.length, offset + 240))}',
  );
}

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(spacingAfter: 0, lineSpacing: 1),
  inlines: <WmlInline>[WmlRun(text: text)],
);

const _mixed =
    'English words, deutsche Wörter, العربية للتخطيط, emoji 😀, '
    'soft\u00adhyphen and tabs\there. ';

WmlSection _section(
  List<WmlBlock> blocks, {
  int columns = 1,
  WmlSectionBreakKind breakKind = WmlSectionBreakKind.nextPage,
}) => WmlSection(
  pageSize: const WmlPageSize(width: 420, height: 390),
  margins: const WmlPageMargins(left: 24, right: 24, top: 30, bottom: 30),
  blocks: blocks,
  columnCount: columns,
  columnSpace: 16,
  columnSep: columns > 1,
  breakKind: breakKind,
  lineNumbers: true,
  differentFirstPage: true,
  differentOddEven: true,
  header: <WmlParagraph>[_paragraph('Running header')],
  firstHeader: <WmlParagraph>[_paragraph('First header')],
  evenHeader: <WmlParagraph>[_paragraph('Even header')],
  footer: <WmlParagraph>[_paragraph('Page')..properties.pageNumberField = true],
);

WmlDocument _corpus({bool structures = false}) => WmlDocument(
  sections: <WmlSection>[
    for (var section = 0; section < 3; section++)
      _section(
        <WmlBlock>[
          for (var index = 0; index < 22; index++)
            _paragraph('$section/$index $_mixed'),
          if (structures)
            WmlTable(
              grid: <double>[140, 180],
              rows: <WmlTableRow>[
                WmlTableRow(
                  cells: <WmlTableCell>[
                    WmlTableCell(
                      blocks: <WmlBlock>[
                        _paragraph('Outer cell $_mixed'),
                        WmlTable(
                          grid: <double>[95],
                          rows: <WmlTableRow>[
                            WmlTableRow(
                              cells: <WmlTableCell>[
                                WmlTableCell(
                                  blocks: <WmlBlock>[
                                    _paragraph('Nested cell $_mixed'),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    WmlTableCell(
                      blocks: <WmlBlock>[_paragraph('Sibling cell $_mixed')],
                    ),
                  ],
                ),
              ],
            ),
          if (structures)
            WmlFrame(
              x: 0,
              y: 0,
              width: 95,
              height: 80,
              anchor: WmlFrameAnchor.margin,
              wrap: WmlFrameWrap.square,
              blocks: <WmlBlock>[_paragraph('Wrapped frame')],
            ),
          for (var index = 22; index < 30; index++)
            _paragraph('$section/$index $_mixed'),
        ],
        columns: section == 1 ? 2 : 1,
        breakKind: section == 1
            ? WmlSectionBreakKind.continuous
            : WmlSectionBreakKind.nextPage,
      ),
  ],
);

void main() {
  setUp(() {
    WordLayoutEngine.incrementalLayout = true;
    WordLayoutEngine.verifyIncrementalLayout = false;
    WordIncrementalLayoutStats.reset();
  });
  tearDown(() {
    WordLayoutEngine.incrementalLayout = true;
    WordLayoutEngine.verifyIncrementalLayout = false;
  });

  test('same-height edits actually converge and reuse the tail', () {
    final document = WmlDocument(
      sections: <WmlSection>[
        _section(<WmlBlock>[
          for (var index = 0; index < 100; index++) _paragraph('Line $index'),
        ]),
      ],
    );
    final engine = WordLayoutEngine(font: null);
    var previous = engine.layout(document, updateFields: false);
    final paragraph = document.paragraphs.elementAt(50);
    for (var index = 0; index < 10; index++) {
      (paragraph.inlines.single as WmlRun).text = 'Edit $index';
      previous = engine.layout(
        document,
        updateFields: false,
        reuse: previous,
        dirtyParagraphs: <WmlParagraph>{paragraph},
      );
      _equivalent(document, previous, 'same-height edit $index');
    }
    expect(WordIncrementalLayoutStats.incremental, 10);
    expect(WordIncrementalLayoutStats.converged, 10);
    expect(WordIncrementalLayoutStats.blocksLaidOut, lessThan(50));
  });

  for (final editText in <bool>[true, false]) {
    test(
      '${editText ? 'text' : 'font'} edits while wrapping invalidate older unwrapped breaks',
      () {
        final lead = _paragraph('Lead');
        final target = _paragraph('Original cached paragraph $_mixed');
        final section = _section(<WmlBlock>[
          lead,
          _paragraph('Spacer A'),
          _paragraph('Spacer B'),
          target,
        ]);
        final document = WmlDocument(sections: <WmlSection>[section]);
        final engine = WordLayoutEngine(font: null);
        var previous = engine.layout(document, updateFields: false);
        _equivalent(document, previous, 'initial unwrapped cache');

        final frame = WmlFrame(
          x: 0,
          y: 0,
          width: 95,
          height: 80,
          anchor: WmlFrameAnchor.margin,
          wrap: WmlFrameWrap.square,
          blocks: <WmlBlock>[],
        );
        section.blocks.insert(1, frame);
        if (editText) {
          WmlRunEdit.replaceRange(target, 0, 0, 'Inserted $_mixed');
        } else {
          for (final run in target.inlines.whereType<WmlRun>()) {
            run.properties
              ..fontSizeHalfPoints = 31
              ..bold = true;
          }
        }
        previous = engine.layout(
          document,
          updateFields: false,
          reuse: previous,
          dirtyParagraphs: <WmlParagraph>{target},
        );
        _equivalent(document, previous, 'edited with a wrapping frame');

        // The target is beyond the one-block dirty margin after removal.
        // Its previous checkpoint still contains the frame, so the engine
        // must lay it out as a clean block instead of converging before it.
        section.blocks.remove(frame);
        WordIncrementalLayoutStats.reset();
        previous = engine.layout(
          document,
          updateFields: false,
          reuse: previous,
          dirtyParagraphs: <WmlParagraph>{lead},
        );
        _equivalent(document, previous, 'clean target after frame removal');
        expect(WordIncrementalLayoutStats.incremental, 1);
        expect(WordIncrementalLayoutStats.converged, 0);
        // The wrapped edit has invalidated the initial unwrapped entries;
        // they must not become readable merely because the frame is gone.
        expect(WordIncrementalLayoutStats.breaksReused, 0);
      },
    );
  }

  for (final structures in <bool>[false, true]) {
    for (final seed in <int>[7, 43, 109]) {
      test('seed $seed structures=$structures stays exact over 48 edits', () {
        final random = Random(seed);
        final document = _corpus(structures: structures);
        final engine = WordLayoutEngine(font: null);
        var previous = engine.layout(document, updateFields: false);
        for (var step = 0; step < 48; step++) {
          final paragraphs = document.paragraphs.toList();
          final paragraph = paragraphs[random.nextInt(paragraphs.length)];
          final dirty = <WmlParagraph>{paragraph};
          switch (step % 8) {
            case 0:
              WmlRunEdit.replaceRange(paragraph, 0, 0, 'Inserted $_mixed');
            case 1:
              WmlRunEdit.replaceRange(
                paragraph,
                0,
                min(12, paragraph.text.length),
                '',
              );
            case 2:
              for (final run in paragraph.inlines.whereType<WmlRun>()) {
                run.properties
                  ..fontSizeHalfPoints = 18 + random.nextInt(20)
                  ..bold = true
                  ..highlight = 'FFFF00';
              }
            case 3:
              paragraph.properties
                ..spacingBefore = random.nextInt(8).toDouble()
                ..spacingAfter = random.nextInt(12).toDouble()
                ..justification = WmlJustification.center;
            case 4:
              final section = document.sections[random.nextInt(3)];
              final inserted = _paragraph('New top-level $_mixed');
              section.blocks.insert(
                random.nextInt(section.blocks.length),
                inserted,
              );
              dirty.add(inserted);
            case 5:
              final section = document.sections[random.nextInt(3)];
              final removable = section.blocks
                  .whereType<WmlParagraph>()
                  .toList();
              section.blocks.remove(
                removable[random.nextInt(removable.length)],
              );
            case 6:
              final other = paragraphs[random.nextInt(paragraphs.length)];
              dirty.add(other);
              WmlRunEdit.replaceRange(paragraph, 0, 0, 'X');
              WmlRunEdit.replaceRange(other, 0, 0, 'Y');
            case 7:
              final section = document.sections[random.nextInt(3)];
              final first = random.nextInt(section.blocks.length);
              final second = random.nextInt(section.blocks.length);
              final held = section.blocks[first];
              section.blocks[first] = section.blocks[second];
              section.blocks[second] = held;
          }
          previous = engine.layout(
            document,
            updateFields: false,
            reuse: previous,
            dirtyParagraphs: dirty,
          );
          _equivalent(
            document,
            previous,
            'seed=$seed structures=$structures step=$step',
          );
        }
        expect(WordIncrementalLayoutStats.incremental, greaterThan(0));
      });
    }
  }

  for (final endnote in <bool>[false, true]) {
    test('notes endnote=$endnote retain full-layout fallback', () {
      final document = _corpus();
      final paragraph = document.paragraphs.elementAt(5);
      paragraph.inlines.add(
        WmlRun(text: '3', noteRefId: 3, noteRefEndnote: endnote),
      );
      final note = WmlNote(
        id: 3,
        endnote: endnote,
        paragraphs: <WmlParagraph>[_paragraph('Native note $_mixed')],
      );
      (endnote ? document.endnotes : document.footnotes).add(note);
      final engine = WordLayoutEngine(font: null);
      final previous = engine.layout(document, updateFields: false);
      WmlRunEdit.replaceRange(paragraph, 0, 0, 'Changed $_mixed');
      final actual = engine.layout(
        document,
        updateFields: false,
        reuse: previous,
        dirtyParagraphs: <WmlParagraph>{paragraph},
      );
      _equivalent(document, actual, 'note fallback');
      expect(WordIncrementalLayoutStats.incremental, 0);
      expect(WordIncrementalLayoutStats.fallbacks, 1);
    });
  }

  test('discarded state and section-list changes use fresh flow', () {
    final document = _corpus();
    final engine = WordLayoutEngine(font: null);
    var previous = engine.layout(document, updateFields: false);
    previous.discardIncrementalState();
    expect(previous.supportsIncrementalReuse, isFalse);
    final paragraph = document.paragraphs.first;
    WmlRunEdit.replaceRange(paragraph, 0, 0, 'Invalidated ');
    previous = engine.layout(
      document,
      updateFields: false,
      reuse: previous,
      dirtyParagraphs: <WmlParagraph>{paragraph},
    );
    _equivalent(document, previous, 'discarded state');
    document.sections.insert(
      0,
      _section(<WmlBlock>[_paragraph('New section')]),
    );
    previous = engine.layout(
      document,
      updateFields: false,
      reuse: previous,
      dirtyParagraphs: <WmlParagraph>{paragraph},
    );
    _equivalent(document, previous, 'section-list change');
    expect(WordIncrementalLayoutStats.fallbacks, 2);
  });
}
