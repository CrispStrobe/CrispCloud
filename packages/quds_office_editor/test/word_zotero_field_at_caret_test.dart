import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitation _citation(String id) => ZoteroCitation(
  citationId: id,
  plainCitation: '($id)',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'type': 'book', 'title': 'Source $id'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

WordEditorController _controller() {
  final document = WmlDocument.empty(text: 'Before ');
  final paragraph = document.paragraphs.single;
  WordZotero.insertCitation(paragraph, _citation('First'));
  WordZotero.insertCitation(paragraph, _citation('Second'));
  paragraph.inlines.add(WmlRun(text: ' after'));
  document.sections.single.blocks.add(
    WmlParagraph(inlines: [WmlRun(text: 'Next paragraph')]),
  );
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'caret selects the exact adjacent citation with half-open boundaries',
    () {
      final controller = _controller();
      final fields = controller.zoteroFields;
      for (final field in fields) {
        for (final offset in [field.start, field.start + 1, field.end - 1]) {
          controller.caret.logicalIndex = offset;
          controller.caret.collapseSelection();
          expect(
            controller.zoteroFieldAtCaret!.citation!.citationId,
            field.citation!.citationId,
          );
        }
      }
      controller.caret.logicalIndex = fields.first.end;
      controller.caret.collapseSelection();
      expect(controller.zoteroFieldAtCaret!.citation!.citationId, 'Second');
      for (final offset in [0, fields.last.end]) {
        controller.caret.logicalIndex = offset;
        controller.caret.collapseSelection();
        expect(controller.zoteroFieldAtCaret, isNull);
      }
      expect(controller.canUndo, isFalse);
      expect(controller.contentRevision, 0);
    },
  );

  test('enclosed forward and backward selections resolve one exact field', () {
    final controller = _controller();
    final first = controller.zoteroFields.first;
    for (final reverse in [false, true]) {
      controller.caret
        ..paragraphIndex = 0
        ..selectionAnchorParagraph = 0
        ..logicalIndex = reverse ? first.start : first.end
        ..selectionAnchor = reverse ? first.end : first.start;
      expect(controller.zoteroFieldAtCaret!.citation!.citationId, 'First');
    }
    controller.caret
      ..logicalIndex = first.end + 1
      ..selectionAnchor = first.start;
    expect(controller.zoteroFieldAtCaret, isNull);
    controller.caret
      ..paragraphIndex = 1
      ..logicalIndex = 1;
    expect(controller.zoteroFieldAtCaret, isNull);
  });

  test(
    'lookup returns current handles after a field was unlinked and undone',
    () {
      final controller = _controller();
      controller.caret.logicalIndex = controller.zoteroFields.first.start + 1;
      controller.caret.collapseSelection();
      controller.unlinkZoteroField(controller.zoteroFieldAtCaret!);
      expect(controller.zoteroFieldAtCaret, isNull);
      controller.undo();
      expect(controller.zoteroFieldAtCaret!.citation!.citationId, 'First');
      final restored = controller.zoteroFieldAtCaret!;
      controller.updateZoteroCitation(
        restored,
        restored.citation!.withItems(
          restored.citation!.items,
          plainCitation: '(Updated)',
        ),
      );
      expect(controller.zoteroFieldAtCaret!.cachedText, '(Updated)');
    },
  );

  test('unrelated active stories never fall back to a body field', () {
    final controller = _controller();
    controller.caret.logicalIndex = controller.zoteroFields.first.start;
    controller.caret.collapseSelection();
    controller.beginHeaderFooterEdit(0, footer: false);
    expect(controller.zoteroFieldAtCaret, isNull);
  });
}
