import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlRun _ref(int id, {bool endnote = false}) => WmlRun(
  text: '$id',
  noteRefId: id,
  noteRefEndnote: endnote,
  properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
);

WmlParagraph _paragraph(int id, {bool endnote = false}) => WmlParagraph(
  inlines: [
    WmlRun(text: 'Before '),
    _ref(id, endnote: endnote),
    WmlRun(text: ' after'),
  ],
);

WmlNote _note(int id, {bool endnote = false}) => WmlNote(
  id: id,
  endnote: endnote,
  paragraphs: [
    WmlParagraph(inlines: [WmlRun(text: 'Note $id')]),
  ],
);

WmlDocument _document(List<int> ids, {bool endnote = false}) => WmlDocument(
  sections: [
    WmlSection(
      blocks: [for (final id in ids) _paragraph(id, endnote: endnote)],
    ),
  ],
  footnotes: endnote ? [] : [for (final id in ids.reversed) _note(id)],
  endnotes: endnote
      ? [for (final id in ids.reversed) _note(id, endnote: true)]
      : [],
);

WmlSectionSource _sectionOptions(String properties) => WmlSectionSource(
  xml: '<w:sectPr xmlns:w="${OfficeNamespaces.w}">$properties</w:sectPr>',
  values: const {},
);

List<LaidOutLine> _body(WmlDocument doc) => WordLayoutEngine(
  font: null,
).layout(doc, updateFields: false).pages.expand((page) => page.lines).toList();

void main() {
  test('imported note marker keeps its native font size, rise and hanging tab', () {
    final package = WordSerializer().write(_document([2]));
    const w = OfficeNamespaces.w;
    package.getPart('/word/styles.xml')!.writeText(
      '<w:styles xmlns:w="$w">'
      '<w:style w:type="character" w:styleId="NoteMarker">'
      '<w:rPr><w:sz w:val="14"/><w:position w:val="4"/>'
      '<w:vertAlign w:val="baseline"/></w:rPr></w:style>'
      '</w:styles>',
    );
    package.getPart('/word/footnotes.xml')!.writeText(
      '<w:footnotes xmlns:w="$w"><w:footnote w:id="2"><w:p>'
      '<w:pPr><w:ind w:left="462" w:hanging="462"/></w:pPr>'
      '<w:r><w:rPr><w:rStyle w:val="NoteMarker"/></w:rPr><w:footnoteRef/></w:r>'
      '<w:r><w:t xml:space="preserve"> </w:t><w:tab/><w:t>Note text</w:t></w:r>'
      '</w:p></w:footnote></w:footnotes>',
    );
    var doc = WordDeserializer().read(package);
    for (var cycle = 0; cycle < 2; cycle++) {
      final marker = doc.footnotes.single.paragraphs.single.inlines
          .whereType<WmlNoteMarker>().single;
      expect(marker.properties.fontSizePoints, 7);
      expect(marker.properties.positionHalfPoints, 4);
      expect(marker.properties.vertAlign, WmlVertAlign.baseline);
      final line = WordLayoutEngine(font: null).layout(doc)
          .pages.expand((page) => page.notes).single;
      final number = line.glyphs.first;
      final text = line.glyphs.firstWhere((g) => g.glyph.codePoint == 0x4e);
      expect(number.fontSize, 7);
      expect(text.x - number.x, closeTo(23.1, .01));
      doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
    }
  });

  test('IDs and storage order do not determine body, note, or pane order', () {
    final doc = _document([42, 8, 71]);
    final source = doc.paragraphs.map((p) => p.text).toList();
    final numbering = WordNoteNumbering(doc);
    expect(numbering.notes.map((n) => n.id), [42, 8, 71]);
    expect(numbering.notes.map(numbering.labelFor), ['1', '2', '3']);
    final layout = WordLayoutEngine(
      font: null,
    ).layout(doc, updateFields: false);
    expect(layout.pages.expand((p) => p.lines).map((l) => l.text), [
      'Before 1 after',
      'Before 2 after',
      'Before 3 after',
    ]);
    expect(layout.pages.expand((p) => p.notes).map((l) => l.text), [
      '1 Note 42',
      '2 Note 8',
      '3 Note 71',
    ]);
    expect(doc.paragraphs.map((p) => p.text), source);
    expect(doc.footnotes.map((n) => n.id), [71, 8, 42]);
  });

  test(
    'earlier insertion and deletion immediately change labels without changing IDs',
    () {
      final doc = _document([9, 3]);
      doc.sections.single.blocks.insert(0, _paragraph(77));
      doc.footnotes.add(_note(77));
      expect(WordNoteNumbering(doc).notes.map((n) => n.id), [77, 9, 3]);
      expect(_body(doc).map((l) => l.text), [
        'Before 1 after',
        'Before 2 after',
        'Before 3 after',
      ]);
      WordNotes.delete(doc, 9, endnote: false);
      expect(WordNoteNumbering(doc).notes.map((n) => n.id), [77, 3]);
      expect(_body(doc).last.text, 'Before 2 after');
    },
  );

  test(
    'shorter display labels retain original reference and following text offsets',
    () {
      final doc = _document([999]);
      final line = _body(doc).single;
      final mark = line.glyphs.singleWhere((g) => g.displayText != null);
      expect(mark.displayText, '1');
      expect(mark.glyph.logicalIndex, 7);
      expect(mark.logicalEnd, 10);
      expect(
        line.glyphs.last.glyph.logicalIndex,
        doc.paragraphs.single.text.length - 1,
      );
      expect(doc.paragraphs.single.text, 'Before 999 after');
    },
  );

  test(
    'longer labels remain one source range through narrow contained layout',
    () {
      final doc = _document([7]);
      doc.sections.single.sourceProperties = _sectionOptions(
        '<w:footnotePr><w:numStart w:val="108"/></w:footnotePr>',
      );
      final paragraph = doc.paragraphs.single;
      doc.sections.single.blocks
        ..clear()
        ..add(
          WmlTable(
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(blocks: [paragraph]),
                ],
              ),
            ],
            grid: [20],
          ),
        );
      final lines = _body(doc);
      final marked = lines
          .where((l) => l.glyphs.any((g) => g.displayText != null))
          .toList();
      expect(
        marked,
        hasLength(1),
        reason: 'A displayed note label never splits across lines',
      );
      final glyphs = marked.single.glyphs
          .where((g) => g.displayText != null)
          .toList();
      expect(glyphs.map((g) => g.glyph.codePoint), '108'.runes);
      expect(glyphs.map((g) => g.glyph.logicalIndex), [7, 7, 7]);
      expect(glyphs.map((g) => g.logicalEnd), [8, 8, 8]);
      expect(glyphs.map((g) => g.displayOffset), [0, 1, 2]);
    },
  );

  test('endnotes use their own body order and Word Roman default', () {
    final doc = _document([31, 6], endnote: true);
    final note = _note(55);
    doc.footnotes.add(note);
    doc.sections.single.blocks.insert(1, _paragraph(55));
    final numbering = WordNoteNumbering(doc);
    expect(numbering.notes.map((n) => n.id), [31, 55, 6]);
    expect(numbering.notes.map(numbering.labelFor), ['i', '1', 'ii']);
    final layout = WordLayoutEngine(
      font: null,
    ).layout(doc, updateFields: false);
    expect(layout.pages.expand((p) => p.notes).map((l) => l.text), [
      '1 Note 55',
      'Endnotes',
      'i Note 31',
      'ii Note 6',
    ]);
  });

  test(
    'native endnote ID zero remains a link, not a reserved display number',
    () {
      final doc = WordDeserializer().readBytes(
        WordSerializer().writeBytes(_document([0], endnote: true)),
      );
      final layout = WordLayoutEngine(
        font: null,
      ).layout(doc, updateFields: false);
      expect(doc.endnotes.single.id, 0);
      expect(layout.pages.expand((p) => p.lines).single.text, 'Before i after');
      expect(layout.pages.expand((p) => p.notes).map((l) => l.text), [
        'Endnotes',
        'i Note 0',
      ]);
    },
  );

  test(
    'tall table slices use full-document labels without duplicating endnote tables',
    () {
      final doc = _document([10, 44]);
      final first = doc.paragraphs.first;
      final second = doc.paragraphs.last;
      final endnote = _note(800, endnote: true);
      endnote.blocks.add(
        WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(
                  blocks: [
                    WmlParagraph(inlines: [WmlRun(text: 'Note table')]),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      doc.endnotes.add(endnote);
      doc.sections.single
        ..pageSize = const WmlPageSize(width: 400, height: 250)
        ..margins = const WmlPageMargins(
          top: 20,
          bottom: 20,
          left: 20,
          right: 20,
        )
        ..blocks.clear()
        ..blocks.addAll([
          first,
          WmlTable(
            grid: [180],
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    blocks: [
                      for (var index = 0; index < 25; index++)
                        WmlParagraph(
                          inlines: [WmlRun(text: 'Row content $index')],
                        ),
                      second,
                      _paragraph(800, endnote: true),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ]);
      final layout = WordLayoutEngine(
        font: null,
      ).layout(doc, updateFields: false);
      expect(layout.pages.length, greaterThan(1));
      final lines = layout.pages.expand((p) => p.lines).toList();
      expect(
        lines.map((l) => l.text),
        containsAll(['Before 1 after', 'Before 2 after', 'Before i after']),
      );
      expect(lines.map((l) => l.text), isNot(contains('Note table')));
      final secondLine = lines.singleWhere((l) => l.text == 'Before 2 after');
      expect(
        secondLine.glyphs.singleWhere((g) => g.displayText != null).logicalEnd,
        9,
      );
      expect(
        layout.pages.expand((p) => p.notes).map((l) => l.text),
        containsAll(['1 Note 10', '2 Note 44', 'i Note 800', 'Note table']),
      );
      expect(
        layout.pages
            .expand((p) => p.frames)
            .where(
              (f) => f.kind == LaidOutBoxKind.tableCell && f.isNoteContent,
            ),
        hasLength(1),
      );
    },
  );

  test('RTL paragraphs keep a multi-digit note label in reading order', () {
    final doc = _document([7]);
    doc.sections.single.sourceProperties = _sectionOptions(
      '<w:footnotePr><w:numStart w:val="108"/></w:footnotePr>',
    );
    final paragraph = doc.paragraphs.single;
    paragraph.properties.rightToLeft = true;
    (paragraph.inlines.first as WmlRun).text = 'قبل ';
    (paragraph.inlines.last as WmlRun).text = ' بعد';
    final line = _body(doc).single;
    final glyphs = line.glyphs.where((g) => g.displayText != null).toList();
    expect(glyphs.map((g) => g.glyph.codePoint), '108'.runes);
    expect(glyphs.map((g) => g.glyph.logicalIndex), [4, 4, 4]);
    expect(glyphs.map((g) => g.logicalEnd), [5, 5, 5]);
    expect(glyphs.first.x, lessThan(glyphs.last.x));
    expect(line.text, contains('108'));
    expect(paragraph.text, 'قبل 7 بعد');
  });

  for (final pair in const {
    'decimal': ['4', '5'],
    'decimalZero': ['04', '05'],
    'upperLetter': ['D', 'E'],
    'lowerLetter': ['d', 'e'],
    'upperRoman': ['IV', 'V'],
    'lowerRoman': ['iv', 'v'],
  }.entries) {
    test(
      '${pair.key} format and non-one start follow native section settings',
      () {
        final doc = _document([21, 88]);
        doc.sections.single.sourceProperties = _sectionOptions(
          '<w:footnotePr><w:numStart w:val="4"/><w:numFmt w:val="${pair.key}"/></w:footnotePr>',
        );
        final numbering = WordNoteNumbering(doc);
        expect(numbering.notes.map(numbering.labelFor), pair.value);
        final saved = WordSerializer().writeBytes(doc);
        final reopened = WordDeserializer().readBytes(saved);
        final again = WordNoteNumbering(reopened);
        expect(again.notes.map(again.labelFor), pair.value);
        expect(reopened.footnotes.map((n) => n.id).toSet(), {21, 88});
      },
    );
  }

  test('section restart and document settings are read without mutation', () {
    final doc = _document([8, 9]);
    doc.sections.add(WmlSection(blocks: [_paragraph(70), _paragraph(20)]));
    doc.footnotes.addAll([_note(70), _note(20)]);
    final package = WordSerializer().write(doc);
    final settings =
        package.getPart('/word/settings.xml') ??
        package.createPart(
          '/word/settings.xml',
          OfficeContentTypes.wordSettings,
          [],
        );
    settings.writeText(
      '<w:settings xmlns:w="${OfficeNamespaces.w}">'
      '<w:footnotePr><w:numFmt w:val="upperLetter"/><w:numStart w:val="3"/>'
      '<w:numRestart w:val="eachSect"/></w:footnotePr></w:settings>',
    );
    final loaded = WordDeserializer().read(package);
    final originalSettings = settings.readText();
    final numbering = WordNoteNumbering(loaded);
    expect(numbering.notes.map(numbering.labelFor), ['C', 'D', 'C', 'D']);
    WordLayoutEngine(font: null).layout(loaded, updateFields: false);
    expect(settings.readText(), originalSettings);
  });

  test(
    'continuous sections carry the preceding counter and only restarts use numStart',
    () {
      final doc = _document([8, 9]);
      doc.sections.single.sourceProperties = _sectionOptions(
        '<w:footnotePr><w:numStart w:val="4"/></w:footnotePr>',
      );
      doc.sections.addAll([
        WmlSection(
          blocks: [_paragraph(70)],
          sourceProperties: _sectionOptions(
            '<w:footnotePr><w:numStart w:val="10"/><w:numRestart w:val="eachSect"/></w:footnotePr>',
          ),
        ),
        WmlSection(
          blocks: [_paragraph(20)],
          sourceProperties: _sectionOptions(
            '<w:footnotePr><w:numStart w:val="80"/><w:numRestart w:val="continuous"/></w:footnotePr>',
          ),
        ),
        WmlSection(blocks: [_paragraph(99)]),
      ]);
      doc.footnotes.addAll([_note(70), _note(20), _note(99)]);
      final loaded = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      final numbering = WordNoteNumbering(loaded);
      expect(numbering.notes.map(numbering.labelFor), [
        '4',
        '5',
        '10',
        '11',
        '12',
      ]);
      expect(numbering.notes.every(numbering.hasExactLabel), isTrue);
    },
  );

  test(
    'unknown page counters remain limited until an explicit section restart',
    () {
      final doc = _document([91]);
      doc.sections.single.sourceProperties = _sectionOptions(
        '<w:footnotePr><w:numRestart w:val="eachPage"/></w:footnotePr>',
      );
      doc.sections.addAll([
        WmlSection(blocks: [_paragraph(92)]),
        WmlSection(
          blocks: [_paragraph(93)],
          sourceProperties: _sectionOptions(
            '<w:footnotePr><w:numStart w:val="5"/><w:numRestart w:val="eachSect"/></w:footnotePr>',
          ),
        ),
        WmlSection(blocks: [_paragraph(94)]),
      ]);
      doc.footnotes.addAll([_note(92), _note(93), _note(94)]);
      final numbering = WordNoteNumbering(doc);
      expect(numbering.notes.map(numbering.labelFor), ['91', '92', '5', '6']);
      expect(numbering.notes.map(numbering.hasExactLabel), [
        false,
        false,
        true,
        true,
      ]);
    },
  );

  test(
    'unsupported formats and out-of-range counters retain native source IDs safely',
    () {
      for (final options in [
        '<w:numFmt w:val="ordinalText"/>',
        '<w:numFmt w:val="lowerRoman"/><w:numStart w:val="4000"/>',
        '<w:numStart w:val="9223372036854775807"/>',
      ]) {
        final doc = _document([91, 92]);
        doc.sections.single.sourceProperties = _sectionOptions(
          '<w:footnotePr>$options</w:footnotePr>',
        );
        final numbering = WordNoteNumbering(doc);
        expect(numbering.notes.map(numbering.labelFor), ['91', '92']);
        expect(
          numbering.notes.every((n) => !numbering.hasExactLabel(n)),
          isTrue,
        );
        expect(
          WordSerializer().write(doc).getPart('/word/document.xml')!.readText(),
          contains(options),
        );
      }
    },
  );

  test('body tables and transparent controls participate; frames do not', () {
    final doc = _document([9]);
    doc.sections.single.blocks.add(
      WmlTable(
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [_paragraph(44)]),
            ],
          ),
        ],
      ),
    );
    doc.sections.single.blocks.add(
      WmlContentControlBlock(
        control: WmlContentControlData(
          xml: '<w:sdt/>',
          sourcePartUri: '/word/document.xml',
          relationships: [],
        ),
        blocks: [_paragraph(55)],
      ),
    );
    doc.footnotes.addAll([_note(44), _note(55)]);
    final numbering = WordNoteNumbering(doc);
    expect(numbering.notes.map((n) => n.id), [9, 44, 55]);
    expect(numbering.notes.map(numbering.labelFor), ['1', '2', '3']);
  });

  test('unanchored definitions have no invented sequence position', () {
    final doc = _document([10]);
    final orphan = _note(99);
    doc.footnotes.insert(0, orphan);
    final numbering = WordNoteNumbering(doc);
    expect(numbering.notes.map((n) => n.id), [10, 99]);
    expect(numbering.labelFor(orphan), '99');
    expect(numbering.hasExactLabel(orphan), isFalse);
    expect(numbering.labelFor(doc.footnotes.last), '1');
  });

  test(
    'unsupported page restart retains native settings and marks preview as limited',
    () {
      final doc = _document([91]);
      doc.sections.single.sourceProperties = _sectionOptions(
        '<w:footnotePr><w:numRestart w:val="eachPage"/></w:footnotePr>',
      );
      final numbering = WordNoteNumbering(doc);
      expect(numbering.hasExactLabel(doc.footnotes.single), isFalse);
      expect(numbering.labelFor(doc.footnotes.single), '91');
      final package = WordSerializer().write(doc);
      expect(
        package.getPart('/word/document.xml')!.readText(),
        contains('eachPage'),
      );
    },
  );

  test(
    'custom marks retain native suppression, adjacent text and do not consume a number',
    () {
      final doc = _document([8, 42, 71]);
      final package = WordSerializer().write(doc);
      package
          .getPart('/word/document.xml')!
          .writeText(
            '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
            '<w:r><w:t>Before </w:t><w:footnoteReference w:id="8"/><w:t> middle </w:t></w:r>'
            '<w:r><w:footnoteReference w:id="42" w:customMarkFollows="1"/><w:t>*</w:t></w:r>'
            '<w:r><w:t> after </w:t><w:footnoteReference w:id="71"/></w:r>'
            '</w:p><w:sectPr/></w:body></w:document>',
          );
      var loaded = WordDeserializer().read(package);
      for (var cycle = 0; cycle < 3; cycle++) {
        final refs = loaded.paragraphs.single.inlines
            .whereType<WmlRun>()
            .where((r) => r.noteRefId != null)
            .toList();
        expect(refs.map((r) => r.noteRefCustomMark), [false, true, false]);
        final numbering = WordNoteNumbering(loaded);
        expect(numbering.notes.map(numbering.labelFor), ['1', '', '2']);
        expect(_body(loaded).single.text, 'Before 1 middle * after 2');
        final clone = WmlClone.paragraph(loaded.paragraphs.single);
        expect(
          clone.inlines
              .whereType<WmlRun>()
              .singleWhere((r) => r.noteRefCustomMark)
              .noteRefId,
          42,
        );
        final saved = WordSerializer().write(loaded);
        final xml = saved.getPart('/word/document.xml')!.readText();
        expect(xml, contains('w:customMarkFollows="1"'));
        expect(xml, contains('*'));
        expect(xml, isNot(contains('\uFFFC')));
        loaded = WordDeserializer().read(saved);
      }
    },
  );
}
