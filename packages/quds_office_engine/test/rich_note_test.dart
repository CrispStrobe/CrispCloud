import 'dart:typed_data';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';
import '../tool/fidelity/note_fixture.dart';

void main() {
  void assertNoOverlap(LaidOutDocument layout, WmlDocument doc) {
    for (final LaidOutPage page in layout.pages) {
      final WmlSection section = doc.sections[page.sectionIndex];
      final List<LaidOutBox> separators = page.frames
          .where((LaidOutBox b) => b.kind == LaidOutBoxKind.footnote)
          .toList();
      if (separators.isNotEmpty) {
        final double top = separators.first.y;
        for (final LaidOutLine line in page.lines) {
          expect(line.y + line.height, lessThanOrEqualTo(top + 0.01));
        }
        for (final LaidOutBox box in page.frames) {
          if (box.isNoteContent || box.kind == LaidOutBoxKind.columnSep) {
            continue;
          }
          expect(box.y + box.height, lessThanOrEqualTo(top + 0.01));
        }
      }
      for (final LaidOutLine line in page.notes) {
        expect(line.y, greaterThanOrEqualTo(section.margins.top));
        expect(
          line.y + line.height,
          lessThanOrEqualTo(
            section.pageSize.height - section.margins.bottom + 0.01,
          ),
        );
      }
    }
  }

  test('dense body reserves footnotes and continues long notes without loss', () {
    final WmlDocument doc = WmlDocument.empty(text: 'Body start');
    doc.sections.first
      ..pageSize = const WmlPageSize(width: 260, height: 260)
      ..margins = const WmlPageMargins(
        top: 20,
        bottom: 20,
        left: 20,
        right: 20,
      );
    WordNotes.insert(
      doc,
      doc.paragraphs.first,
      endnote: false,
      text: List<String>.generate(
        180,
        (int i) => 'N${i.toString().padLeft(3, '0')}',
      ).join(' '),
    );
    for (var i = 0; i < 30; i++) {
      doc.sections.first.blocks.add(
        WmlParagraph(
          inlines: <WmlInline>[
            WmlRun(
              text:
                  'Body paragraph $i with enough text to wrap onto several lines.',
            ),
          ],
        ),
      );
    }
    final LaidOutDocument layout = WordLayoutEngine(font: null).layout(doc);
    assertNoOverlap(layout, doc);
    final String notes = layout.pages
        .expand((LaidOutPage p) => p.notes)
        .map((LaidOutLine l) => l.text)
        .join(' ');
    for (var i = 0; i < 180; i++) {
      expect(
        RegExp('N${i.toString().padLeft(3, '0')}').allMatches(notes),
        hasLength(1),
      );
    }
    expect(
      layout.pages.where((LaidOutPage p) => p.notes.isNotEmpty).length,
      greaterThan(1),
    );
    expect(layout.pages.first.notes, isNotEmpty);
    expect(
      layout.pages
          .expand((LaidOutPage p) => p.lines)
          .map((LaidOutLine l) => l.text)
          .join(' '),
      contains('paragraph 29'),
    );
  });

  test(
    'rich note layout retains styles, wraps, tables, pictures and links',
    () {
      final WmlDocument doc = richNoteFixture();
      final LaidOutDocument layout = WordLayoutEngine(font: null).layout(doc);
      assertNoOverlap(layout, doc);
      final List<LaidOutGlyph> glyphs = layout.pages
          .expand((LaidOutPage p) => p.notes)
          .expand((LaidOutLine l) => l.glyphs)
          .toList();
      expect(
        glyphs.any(
          (LaidOutGlyph g) => g.bold && g.color == '008844' && g.fontSize == 12,
        ),
        isTrue,
      );
      expect(
        glyphs.any(
          (LaidOutGlyph g) => g.hyperlink?.url == 'https://example.com/note',
        ),
        isTrue,
      );
      expect(
        layout.pages
            .expand((LaidOutPage p) => p.frames)
            .where((LaidOutBox b) => b.isNoteContent && b.visual != null),
        hasLength(1),
      );
      expect(
        layout.pages
            .expand((LaidOutPage p) => p.frames)
            .where(
              (LaidOutBox b) =>
                  b.isNoteContent && b.kind == LaidOutBoxKind.tableCell,
            ),
        hasLength(1),
      );
    },
  );

  test('column flow leaves the note band clear', () {
    final WmlDocument doc = WmlDocument.empty(text: 'First');
    doc.sections.first
      ..pageSize = const WmlPageSize(width: 300, height: 240)
      ..margins = const WmlPageMargins(top: 20, bottom: 20, left: 20, right: 20)
      ..columnCount = 2;
    for (var i = 0; i < 16; i++) {
      final WmlParagraph p = WmlParagraph(
        inlines: <WmlInline>[WmlRun(text: 'Column text $i')],
      );
      doc.sections.first.blocks.add(p);
      if (i == 7 || i == 12) {
        WordNotes.insert(doc, p, endnote: false, text: 'Column note $i');
      }
    }
    final LaidOutDocument layout = WordLayoutEngine(font: null).layout(doc);
    assertNoOverlap(layout, doc);
    expect(
      layout.pages
          .expand((LaidOutPage p) => p.notes)
          .map((LaidOutLine l) => l.text),
      containsAll(<String>['1. Column note 7', '2. Column note 12']),
    );
  });

  test('references in table cells reserve a note band', () {
    final WmlDocument doc = WmlDocument.empty(text: 'Table heading');
    doc.sections.first
      ..pageSize = const WmlPageSize(width: 260, height: 260)
      ..margins = const WmlPageMargins(
        top: 20,
        bottom: 20,
        left: 20,
        right: 20,
      );
    final WmlParagraph cell = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: 'Cell reference')],
    );
    doc.sections.first.blocks.add(
      WmlTable(
        grid: <double>[180],
        rows: <WmlTableRow>[
          WmlTableRow(
            cells: <WmlTableCell>[
              WmlTableCell(blocks: <WmlBlock>[cell]),
            ],
          ),
        ],
      ),
    );
    WordNotes.insert(
      doc,
      cell,
      endnote: false,
      text: 'Note belonging to the table',
    );
    final LaidOutDocument layout = WordLayoutEngine(font: null).layout(doc);
    assertNoOverlap(layout, doc);
    expect(
      layout.pages
          .expand((LaidOutPage p) => p.notes)
          .map((LaidOutLine l) => l.text)
          .join(' '),
      contains('Note belonging to the table'),
    );
  });

  test('body pictures skip pages occupied by continuing footnotes', () {
    final WmlDocument doc = richNoteFixture();
    doc.sections.first
      ..pageSize = const WmlPageSize(width: 280, height: 280)
      ..margins = const WmlPageMargins(
        top: 20,
        bottom: 20,
        left: 20,
        right: 20,
      );
    doc.footnotes.single.text = List<String>.generate(
      150,
      (int i) => 'Long$i',
    ).join(' ');
    final LaidOutDocument layout = WordLayoutEngine(font: null).layout(doc);
    assertNoOverlap(layout, doc);
    expect(
      layout.pages
          .expand((LaidOutPage p) => p.frames)
          .where((LaidOutBox b) => !b.isNoteContent && b.visual != null),
      hasLength(1),
    );
  });

  test(
    'rich note blocks, run styles and part-owned media survive editing',
    () async {
      WmlDocument doc = richNoteFixture();
      final Uint8List image =
          doc.footnotes.single.visuals.single.visual.imageBytes!;
      expect(image, isNot(doc.visuals.single.visual.imageBytes));
      for (var cycle = 0; cycle < 3; cycle++) {
        final WmlNote note = doc.footnotes.single;
        expect(
          note.blocks.map((WmlBlock b) => b.runtimeType.toString()),
          <String>['WmlParagraph', 'WmlTable', 'WmlVisual', 'WmlParagraph'],
        );
        final WmlRun run = note.paragraphs.first.inlines
            .whereType<WmlRun>()
            .firstWhere((WmlRun r) => r.text.contains('Rich note'));
        expect(run.properties.bold, isTrue);
        expect(run.properties.color, '008844');
        expect(run.properties.fontSizeHalfPoints, 24);
        expect(note.text, contains('Note table'));
        expect(note.visuals.single.visual.imageBytes, image);
        expect(
          note.paragraphs.last.inlines
              .whereType<WmlRun>()
              .single
              .hyperlink
              ?.url,
          'https://example.com/note',
        );
        WmlRunEdit.replaceRange(doc.paragraphs.first, 0, 8, 'Modified');
        doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
      }
    },
  );
  test('legacy paragraph view edits keep nonparagraph note blocks', () {
    final WmlNote note = richNoteFixture().footnotes.single;
    note.paragraphs.insert(
      1,
      WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Inserted')]),
    );
    expect(note.paragraphs, hasLength(3));
    note.paragraphs.removeAt(0);
    expect(note.blocks.whereType<WmlTable>(), hasLength(1));
    expect(note.visuals, hasLength(1));
    note.text = 'Replacement';
    expect(note.blocks, hasLength(1));
    expect(note.text, 'Replacement');
  });
}
