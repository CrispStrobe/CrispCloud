import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument openFixture() => WordDeserializer().readBytes(
  File('test/fixtures/fidelity/word.docx').readAsBytesSync(),
);

void main() {
  test('mixed note references and all note paragraphs appear on the page', () {
    final LaidOutDocument layout = WordLayoutEngine(
      font: null,
    ).layout(openFixture());
    expect(layout.pages, hasLength(1));
    final List<String?> lines = layout.pages.single.notes
        .map((LaidOutLine line) => line.text)
        .toList();
    expect(
      lines,
      containsAll(<String>[
        '12. Footnote text',
        'Note link',
        'Endnotes',
        '3. Endnote text',
      ]),
    );
  });

  test('multiple footnotes in one paragraph do not hide each other', () {
    final WmlDocument doc = WmlDocument.empty(text: 'Body');
    for (final String text in <String>['First', 'Second']) {
      WordNotes.insert(doc, doc.paragraphs.first, endnote: false, text: text);
    }
    WordNotes.insert(doc, doc.paragraphs.first, endnote: true, text: 'End');
    final LaidOutDocument layout = WordLayoutEngine(font: null).layout(doc);
    expect(
      layout.pages.single.notes.map((LaidOutLine l) => l.text),
      containsAll(<String>['1. First', '2. Second', '1. End']),
    );
  });

  test('multiline endnotes continue onto additional pages', () {
    final WmlDocument doc = WmlDocument.empty(text: 'Body');
    WordNotes.insert(
      doc,
      doc.paragraphs.first,
      endnote: true,
      text: List<String>.generate(100, (int i) => 'Line $i').join('\n'),
    );
    final LaidOutDocument layout = WordLayoutEngine(font: null).layout(doc);
    expect(layout.pages.length, greaterThan(1));
    final List<LaidOutLine> notes = layout.pages
        .expand((LaidOutPage p) => p.notes)
        .toList();
    expect(notes.map((LaidOutLine l) => l.text), contains('Line 99'));
    for (final LaidOutLine line in notes) {
      expect(
        line.y + line.height,
        lessThanOrEqualTo(
          doc.sections.first.pageSize.height -
              doc.sections.first.margins.bottom,
        ),
      );
    }
  });

  test('custom numbering definitions preserve visible labels after export', () {
    WmlDocument doc = openFixture();
    final String? label = doc.paragraphs.elementAt(3).properties.listLabel;
    expect(label, '1. ');
    for (var cycle = 0; cycle < 3; cycle++) {
      doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
      expect(doc.paragraphs.elementAt(3).properties.listLabel, label);
    }
  });

  test('table style id, border color and border width survive export', () {
    final WmlDocument doc = openFixture();
    final WmlTable table = doc.sections.first.blocks
        .whereType<WmlTable>()
        .single;
    // The authored source has no direct or inherited borders. Make the edit
    // explicit instead of relying on the old import default that added borders.
    expect(table.properties.borders, isFalse);
    table.properties
      ..styleId = 'TableCustom'
      ..borders = true
      ..borderColor = '123456'
      ..borderWidth = 2;
    final WmlTable after = WordDeserializer()
        .readBytes(WordSerializer().writeBytes(doc))
        .sections
        .first
        .blocks
        .whereType<WmlTable>()
        .single;
    expect(after.properties.styleId, 'TableCustom');
    expect(after.properties.borderColor, '123456');
    expect(after.properties.borderWidth, 2);
  });

  test(
    'explicit default formatting overrides a non-default paragraph style',
    () {
      final WmlParagraph p = openFixture().paragraphs.elementAt(1);
      final WmlRun run = p.inlines.whereType<WmlRun>().first;
      expect(p.properties.spacingBefore, 0);
      expect(p.properties.spacingAfter, 8);
      expect(p.properties.justification, WmlJustification.left);
      expect(run.properties.bold, isFalse);
      expect(run.properties.italic, isFalse);
      expect(run.properties.color, '000000');
      expect(run.properties.fontSizeHalfPoints, 22);
      expect(run.properties.highlight, 'FFFF00');
    },
  );

  test('style defaults apply when direct formatting is absent', () {
    final WmlParagraph p = openFixture().paragraphs.first;
    expect(p.properties.headingLevel, 1);
    expect(p.inlines.whereType<WmlRun>().first.properties.bold, isTrue);
    expect(
      p.inlines.whereType<WmlRun>().first.properties.fontSizeHalfPoints,
      32,
    );
  });

  test('notes resolve hyperlinks against their own part', () {
    final WmlNote note = openFixture().footnotes.single;
    expect(
      note.paragraphs.last.inlines.whereType<WmlRun>().single.hyperlink?.url,
      'https://example.com/note',
    );
  });

  test(
    'format/extract/insert preserve multi-digit note reference identity',
    () {
      final WmlDocument doc = openFixture();
      final WmlParagraph p = doc.paragraphs.elementAt(1);
      final int start = 'Body text'.length;
      WmlRunEdit.applyRange(
        p,
        start,
        start + 2,
        (WmlRunProps r) => r.bold = true,
      );
      expect(
        p.inlines.whereType<WmlRun>().where((WmlRun r) => r.noteRefId == 12),
        hasLength(1),
      );
      final List<WmlRun> copied = WmlRunEdit.extractRuns(p, start, start + 2);
      final WmlParagraph target = WmlParagraph();
      WmlRunEdit.insertRuns(target, 0, copied);
      expect(target.inlines.whereType<WmlRun>().single.noteRefId, 12);
    },
  );

  test('adjacent reference marks never coalesce into ordinary text', () {
    final WmlParagraph p = WmlParagraph(
      inlines: <WmlInline>[
        WmlRun(text: '1', noteRefId: 1),
        WmlRun(text: '2', noteRefId: 2),
        WmlRun(text: ' text'),
      ],
    );
    WmlRunEdit.coalesce(p);
    expect(p.inlines, hasLength(3));
  });

  test(
    'formatting part of a multi-digit note does not duplicate its reference',
    () {
      final WmlParagraph p = WmlParagraph(
        inlines: <WmlInline>[WmlRun(text: '12', noteRefId: 12)],
      );
      WmlRunEdit.applyRange(p, 0, 1, (WmlRunProps r) => r.bold = true);
      expect(
        p.inlines.whereType<WmlRun>().where((WmlRun r) => r.noteRefId == 12),
        hasLength(1),
      );
    },
  );

  test('deleting a note does not erase unrelated bracketed prose', () {
    final WmlDocument doc = WmlDocument.empty(text: 'Citation [1] must remain');
    WordNotes.insert(doc, doc.paragraphs.first, endnote: false, text: 'Note');
    WordNotes.delete(doc, 1, endnote: false);
    expect(doc.paragraphs.first.text, 'Citation [1] must remain');
  });

  test('repeated export does not accumulate note-body whitespace', () {
    WmlDocument doc = openFixture();
    final String original = doc.footnotes.single.paragraphs.first.text;
    for (var cycle = 0; cycle < 3; cycle++) {
      doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
      expect(
        doc.footnotes.single.paragraphs.first.text,
        original,
        reason: 'cycle $cycle',
      );
    }
  });

  test('list style numbering and indents survive repeated save', () {
    WmlDocument doc = openFixture();
    for (var cycle = 0; cycle < 3; cycle++) {
      doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
      final WmlStyle style = doc.styles.singleWhere(
        (WmlStyle s) => s.id == 'ListCustom',
      );
      expect(style.numId, 5);
      expect(style.indent?.left, 36);
      expect(style.indent?.hanging, 18);
    }
  });

  test('WordStyles.apply uses document list properties', () {
    final WmlDocument doc = openFixture();
    final WmlParagraph p = doc.paragraphs.first;
    WordStyles.apply(p, 'ListCustom', document: doc);
    expect(p.properties.numId, 5);
    expect(p.properties.ilvl, 0);
    expect(p.properties.indent.left, 36);
    WordStyles.apply(p, 'Normal', document: doc);
    expect(p.properties.numId, isNull);
    expect(p.properties.indent.left, 0);
  });
}
