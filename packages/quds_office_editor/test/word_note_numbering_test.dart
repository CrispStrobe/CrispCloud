import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlDocument _document(int id, {int start = 1}) {
  final paragraph = WmlParagraph(
    inlines: [
      WmlRun(text: 'Before '),
      WmlRun(
        text: '$id',
        noteRefId: id,
        properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
      ),
      WmlRun(text: ' after'),
    ],
  );
  return WmlDocument(
    sections: [
      WmlSection(
        blocks: [paragraph],
        sourceProperties: WmlSectionSource(
          xml:
              '<w:sectPr xmlns:w="${OfficeNamespaces.w}"><w:footnotePr>'
              '<w:numStart w:val="$start"/></w:footnotePr></w:sectPr>',
          values: const {},
        ),
      ),
    ],
    footnotes: [
      WmlNote(
        id: id,
        endnote: false,
        paragraphs: [
          WmlParagraph(inlines: [WmlRun(text: 'Original note')]),
        ],
      ),
    ],
  );
}

LaidOutLine _line(WmlDocument doc) => WordLayoutEngine(
  font: null,
).layout(doc, updateFields: false).pages.single.lines.single;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final pair in const [(999, 1), (7, 108), (10, 10)]) {
    test(
      'display ${pair.$2} for native ID ${pair.$1} paints and hit-tests atomically',
      () {
        final doc = _document(pair.$1, start: pair.$2);
        final paragraph = doc.paragraphs.single.text;
        final line = _line(doc);
        PaintRunText.fitLine(line, paragraph);
        final segments = PaintRunText.paintSegments(line).toList();
        expect(
          segments.map((run) => PaintRunText.runText(paragraph, run)).join(),
          'Before ${pair.$2} after',
        );
        final mark = segments.singleWhere(
          (run) => run.first.displayText != null,
        );
        final left = mark.first.x;
        final right = mark.last.x + mark.last.advance;
        final sourceStart = 7;
        final sourceEnd = 7 + '${pair.$1}'.length;
        expect(right, greaterThan(left));
        expect(
          PaintRunText.hitLogicalIndexOnLine(
            line,
            left + (right - left) * .1,
            paragraph: paragraph,
          ),
          sourceStart,
        );
        expect(
          PaintRunText.hitLogicalIndexOnLine(
            line,
            left + (right - left) * .9,
            paragraph: paragraph,
          ),
          sourceEnd,
        );
        expect(
          CaretEngine.hitLogicalIndex(line, left + (right - left) * .1),
          sourceStart,
        );
        expect(
          CaretEngine.hitLogicalIndex(line, left + (right - left) * .9),
          sourceEnd,
        );
        expect(
          PaintRunText.caretXOnLine(line, sourceStart, paragraph: paragraph),
          closeTo(left, .01),
        );
        expect(
          PaintRunText.caretXOnLine(line, sourceEnd, paragraph: paragraph),
          closeTo(right, .01),
        );
        final selected = CaretEngine.rangeRectsOnLine(
          line,
          line.y,
          line.height,
          sourceStart,
          sourceEnd,
        );
        expect(selected, hasLength(1));
        expect(selected.single.left, closeTo(left, .01));
        expect(selected.single.right, closeTo(right, .01));
        final stops = CaretEngine.visualStops(line).map((s) => s.index).toSet();
        expect(stops, containsAll([sourceStart, sourceEnd]));
        for (var index = sourceStart + 1; index < sourceEnd; index++) {
          expect(stops, isNot(contains(index)));
        }
        expect(doc.paragraphs.single.text, paragraph);
      },
    );
  }

  test(
    'editing after a shortened label still uses the original source range',
    () {
      final word = WordEditorController(document: _document(999));
      addTearDown(word.dispose);
      word.caret
        ..logicalIndex = 10
        ..selectionAnchor = 10;
      word.insertText('!');
      expect(word.document.paragraphs.single.text, 'Before 999! after');
      expect(
        word.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .singleWhere((r) => r.noteRefId != null)
            .noteRefId,
        999,
      );
      expect(word.laidOut.pages.single.lines.single.text, 'Before 1! after');
      word.undo();
      expect(word.document.paragraphs.single.text, 'Before 999 after');
      expect(word.laidOut.pages.single.lines.single.text, 'Before 1 after');
    },
  );

  test(
    'earlier inserted notes renumber on insert, undo and redo without ID changes',
    () {
      final word = WordEditorController(document: _document(999));
      addTearDown(word.dispose);
      final original = word.document.footnotes.single;
      word.caret
        ..logicalIndex = 0
        ..selectionAnchor = 0;
      word.insertFootnote(text: 'Earlier note');
      expect(word.document.footnotes.map((n) => n.id), [999, 1000]);
      expect(word.laidOut.pages.single.lines.single.text, '1Before 2 after');
      final source = word.document.paragraphs.single.text;
      final caret = word.caret.logicalIndex;
      word.relayout();
      expect(word.document.paragraphs.single.text, source);
      expect(word.caret.logicalIndex, caret);
      word.undo();
      expect(word.document.footnotes.single, same(original));
      expect(word.laidOut.pages.single.lines.single.text, 'Before 1 after');
      word.redo();
      expect(word.laidOut.pages.single.lines.single.text, '1Before 2 after');
    },
  );

  testWidgets(
    'notes pane shows body order and keeps edit identity after insertion',
    (tester) async {
      final word = WordEditorController(document: _document(999));
      addTearDown(word.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: QudsWordEditor(
                controller: word,
                config: const OfficeSurfaceConfig(showNotesPane: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final existing = find.byKey(const ValueKey<String>('notes-edit-999'));
      expect(find.text('Note 1'), findsOneWidget);
      final before = tester.widget<TextField>(existing);
      word.caret
        ..logicalIndex = 0
        ..selectionAnchor = 0;
      word.insertFootnote(text: 'Earlier note');
      await tester.pump();
      final inserted = find.byKey(const ValueKey<String>('notes-edit-1000'));
      expect(find.text('Note 1'), findsOneWidget);
      expect(find.text('Note 2'), findsOneWidget);
      expect(
        tester.getTopLeft(inserted).dy,
        lessThan(tester.getTopLeft(existing).dy),
      );
      final after = tester.widget<TextField>(existing);
      expect(after.controller, same(before.controller));
      expect(after.focusNode, same(before.focusNode));
      expect(after.controller!.text, 'Original note');
    },
  );

  testWidgets('limited and orphaned note labels identify source IDs explicitly', (
    tester,
  ) async {
    final doc = _document(91);
    doc.sections.single.sourceProperties = WmlSectionSource(
      xml:
          '<w:sectPr xmlns:w="${OfficeNamespaces.w}"><w:footnotePr><w:numRestart w:val="eachPage"/></w:footnotePr></w:sectPr>',
      values: const {},
    );
    doc.footnotes.add(
      WmlNote(
        id: 99,
        endnote: false,
        paragraphs: [
          WmlParagraph(inlines: [WmlRun(text: 'Orphaned note')]),
        ],
      ),
    );
    final word = WordEditorController(document: doc);
    addTearDown(word.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 700,
            child: QudsWordEditor(
              controller: word,
              config: const OfficeSurfaceConfig(showNotesPane: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Note (source ID 91)'), findsOneWidget);
    expect(find.text('Note (source ID 99)'), findsOneWidget);
    expect(find.text('Note 91'), findsNothing);
    expect(find.byKey(const ValueKey<String>('notes-edit-91')), findsOneWidget);
  });
}
