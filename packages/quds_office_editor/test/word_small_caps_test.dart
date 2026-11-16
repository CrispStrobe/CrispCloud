import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller(String text) {
  final document = WmlDocument.empty(text: text);
  document.paragraphs.single.inlines.whereType<WmlRun>().single.properties =
      WmlRunProps(smallCaps: true, fontSizeHalfPoints: 24);
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test(
    'editor paints measured capitals while keeping the source and caret',
    () {
      final controller = _controller('Smith');
      final paragraph = controller.document.paragraphs.single;
      final line = controller.documentLaidOut.pages.single.lines.single;
      final segments = PaintRunText.paintSegments(line).toList();
      expect(
        segments.map((run) => PaintRunText.runText(paragraph.text, run)).join(),
        'SMITH',
      );
      expect(line.glyphs.first.fontSize, 12);
      expect(
        line.glyphs.skip(1).every((g) => (g.fontSize - 9.6).abs() < 0.001),
        isTrue,
      );
      final last = line.glyphs.last;
      expect(
        CaretEngine.caretX(line, 5),
        closeTo(last.x + last.advance, 0.001),
      );
      expect(CaretEngine.hitLogicalIndex(line, last.x + last.advance * 0.8), 5);
      expect(paragraph.text, 'Smith');
    },
  );

  test(
    'expanded display clusters have only their original caret boundaries',
    () {
      final controller = _controller('a\u0301𐐨');
      final line = controller.documentLaidOut.pages.single.lines.single;
      final firstCluster = line.glyphs
          .where((g) => g.glyph.logicalIndex == 0)
          .toList();
      expect(firstCluster, isNotEmpty);
      expect(firstCluster.every((g) => g.logicalEnd == 2), isTrue);
      final left = firstCluster.first.x;
      final right = firstCluster.last.x + firstCluster.last.advance;
      expect(CaretEngine.caretX(line, 2), closeTo(right, 0.001));
      expect(CaretEngine.hitLogicalIndex(line, left + (right - left) * 0.2), 0);
      expect(CaretEngine.hitLogicalIndex(line, left + (right - left) * 0.8), 2);
      expect(controller.document.paragraphs.single.text, 'a\u0301𐐨');
    },
  );

  test('mixed strikethrough does not share one paint run', () {
    final controller = _controller('AB');
    final paragraph = controller.document.paragraphs.single;
    WmlRunEdit.applyRange(paragraph, 0, 1, (props) => props.strike = true);
    final line = WordLayoutEngine(
      font: null,
    ).layout(controller.document).pages.single.lines.single;
    expect(
      PaintRunText.samePaintRun(line.glyphs.first, line.glyphs.last),
      isFalse,
    );
  });

  test(
    'native small-capital refresh supports one undo step and DOCX reopen',
    () {
      final citation = ZoteroCitation(
        citationId: 'editor-small-caps',
        plainCitation: 'Müller, 12',
        items: [
          ZoteroCitationItem.fromCsl(
            itemData: {'type': 'book', 'title': 'Book'},
            uris: ['http://zotero.org/users/42/items/ABCD1234'],
            locator: '12',
          ),
        ],
      );
      final document = WmlDocument.empty(text: 'Before  after');
      WordZotero.insertCitation(document.paragraphs.single, citation, index: 7);
      final controller = WordEditorController(document: document);
      addTearDown(controller.dispose);
      final tx = controller.beginZoteroTransaction(documentId: 'small-caps');
      Object? call(String name, [List<Object?> args = const []]) =>
          tx.session.handle(name, ['small-caps', ...args]);
      final fields = call('Document.getFields', ['Http']) as List;
      final id = (fields.single as Map)['id'];
      call('Field.setCode', [
        id,
        'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
      ]);
      call('Field.setText', [
        id,
        '<span style="font-variant:small-caps">Müller</span>, 12',
        true,
      ]);
      call('Document.complete');
      tx.apply();
      void check(WmlDocument value) {
        final field = WordZotero.fields(value).single;
        expect(field.cachedText, 'Müller, 12');
        expect(
          field.paragraph.inlines
              .whereType<WmlRun>()
              .singleWhere((r) => r.text == 'Müller')
              .properties
              .smallCaps,
          isTrue,
        );
        expect(
          field.paragraph.inlines
              .whereType<WmlRun>()
              .singleWhere((r) => r.text == ', 12')
              .properties
              .smallCaps,
          isFalse,
        );
      }

      check(controller.document);
      check(WordDeserializer().readBytes(controller.saveBytes()));
      controller.undo();
      expect(controller.zoteroFields.single.run!.properties.smallCaps, isFalse);
      expect(controller.canUndo, isFalse);
      controller.redo();
      check(controller.document);
    },
  );
}
