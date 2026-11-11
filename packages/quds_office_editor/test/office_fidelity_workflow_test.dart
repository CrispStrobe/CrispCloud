import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

Uint8List fidelityFixture() {
  for (final String prefix in <String>['../', 'packages/']) {
    final File file = File(
      '${prefix}quds_office_engine/test/fixtures/fidelity/word.docx',
    );
    if (file.existsSync()) return file.readAsBytesSync();
  }
  throw StateError('Run from the editor package or CrispCloud root.');
}

WordEditorController openFixture() {
  final WordEditorController c = WordEditorController.fromBytes(
    fidelityFixture(),
  );
  addTearDown(c.dispose);
  return c;
}

List<int?> references(WmlDocument doc) => <int?>[
  for (final WmlParagraph p in doc.paragraphs)
    for (final WmlRun r in p.inlines.whereType<WmlRun>())
      if (r.noteRefId != null) r.noteRefId,
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('list commands preserve imported definitions and support undo redo', () {
    final WordEditorController c = openFixture();
    final part = c.document.package!.getPart('/word/numbering.xml')!;
    part.writeText(
      part.readText().replaceFirst(
        '</w:numbering>',
        '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="◆"/></w:lvl></w:abstractNum>'
            '<w:abstractNum w:abstractNumId="2"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="upperRoman"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum>'
            '<w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>'
            '<w:num w:numId="2"><w:abstractNumId w:val="2"/></w:num></w:numbering>',
      ),
    );
    c.jumpToParagraph(2);
    c.applyList(numbered: true);
    final int? id = c.document.paragraphs.elementAt(2).properties.numId;
    expect(id, isNot(anyOf(1, 2, 5, null)));
    c.undo();
    expect(c.document.paragraphs.elementAt(2).properties.numId, isNull);
    c.redo();
    expect(c.document.paragraphs.elementAt(2).properties.numId, id);
    expect(
      WordDeserializer()
          .readBytes(c.saveBytes())
          .paragraphs
          .elementAt(2)
          .properties
          .listLabel,
      '1. ',
    );
    c.toggleList(numbered: false);
    expect(c.document.paragraphs.elementAt(2).properties.numId, isNull);
    c.toggleList(numbered: false);
    final WmlDocument reopened = WordDeserializer().readBytes(c.saveBytes());
    expect(reopened.paragraphs.elementAt(2).properties.listLabel, '• ');
    expect(reopened.paragraphs.elementAt(3).properties.listLabel, '1. ');
  });
  test('host async save preserves notes, links and images', () async {
    final WordEditorController c = openFixture();
    final Uint8List bytes = await c.saveBytesAsync();
    final WordEditorController reopened = WordEditorController.fromBytes(bytes);
    addTearDown(reopened.dispose);
    expect(references(reopened.document), <int>[12, 3]);
    expect(
      reopened.document.visuals.single.visual.imageBytes,
      c.document.visuals.single.visual.imageBytes,
    );
    expect(
      reopened.document.footnotes.single.paragraphs.last.inlines
          .whereType<WmlRun>()
          .single
          .hyperlink
          ?.url,
      'https://example.com/note',
    );
    final File exported = File('build/fidelity/unchanged-controller.docx');
    exported.parent.createSync(recursive: true);
    exported.writeAsBytesSync(bytes);
  });
  test('format undo redo preserves reference identity', () {
    final WordEditorController c = openFixture();
    c.jumpToParagraph(1);
    c.selectParagraphAtCaret();
    c.applyRunFormat((WmlRunProps r) => r.italic = true);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(references(c.document), <int>[12, 3]);
      c.undo();
      expect(references(c.document), <int>[12, 3]);
      c.redo();
    }
    expect(references(WordDeserializer().readBytes(c.saveBytes())), <int>[
      12,
      3,
    ]);
  });
  test('paragraph split and undo preserve styled runs and notes', () {
    final WordEditorController c = openFixture();
    c.jumpToParagraph(1);
    c.caret.logicalIndex = 4;
    c.caret.collapseSelection();
    c.insertParagraphBreak();
    final List<WmlParagraph> ps = c.document.paragraphs.toList();
    expect(ps[1].text, 'Body');
    expect(ps[2].text, ' text123');
    expect(references(c.document), <int>[12, 3]);
    expect(
      ps[2].inlines.whereType<WmlRun>().first.properties.highlight,
      'FFFF00',
    );
    expect(identical(ps[1].properties, ps[2].properties), isFalse);
    c.undo();
    expect(c.document.paragraphs.elementAt(1).text, 'Body text123');
    expect(references(c.document), <int>[12, 3]);
    c.redo();
    expect(references(c.document), <int>[12, 3]);
  });
  test(
    'custom style uses document catalog and undo restores direct values',
    () {
      final WordEditorController c = openFixture();
      c.jumpToParagraph(1);
      c.applyStyle('ListCustom');
      expect(c.document.paragraphs.elementAt(1).properties.numId, 5);
      c.undo();
      final WmlParagraph p = c.document.paragraphs.elementAt(1);
      expect(p.properties.spacingBefore, 0);
      expect(p.properties.spacingAfter, 8);
      expect(p.inlines.whereType<WmlRun>().first.properties.bold, isFalse);
      c.redo();
      c.undo();
      expect(p.properties.spacingBefore, 0);
      expect(references(c.document), <int>[12, 3]);
    },
  );
  test('paragraph format history does not mutate the undo snapshot', () {
    final WordEditorController c = openFixture();
    c.jumpToParagraph(1);
    c.applyParagraphFormat((WmlParagraphProps p) => p.spacingBefore += 6);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(c.document.paragraphs.elementAt(1).properties.spacingBefore, 6);
      c.undo();
      expect(c.document.paragraphs.elementAt(1).properties.spacingBefore, 0);
      c.redo();
    }
  });
  for (final bool endnote in <bool>[false, true]) {
    test(
      '${endnote ? 'endnote' : 'footnote'} inserts at caret and survives history',
      () {
        final WordEditorController c = WordEditorController(
          document: WmlDocument.empty(text: 'abcdef'),
        );
        addTearDown(c.dispose);
        c.caret.logicalIndex = 3;
        c.caret.collapseSelection();
        c.insertFootnote(text: 'New note', endnote: endnote);
        expect(c.document.paragraphs.first.text, 'abc1def');
        c.undo();
        expect(c.document.paragraphs.first.text, 'abcdef');
        c.redo();
        expect(c.document.paragraphs.first.text, 'abc1def');
        final WmlDocument after = WordDeserializer().readBytes(c.saveBytes());
        expect(
          (endnote ? after.endnotes : after.footnotes).single.text,
          'New note',
        );
        expect(references(after), <int>[1]);
      },
    );
  }
}
