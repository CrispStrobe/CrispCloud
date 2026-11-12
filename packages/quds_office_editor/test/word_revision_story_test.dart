import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WordEditorController _controller() {
  final controller = WordEditorController(
    document: WmlDocument.empty(text: 'Body content must stay'),
  );
  addTearDown(controller.dispose);
  return controller;
}

List<WmlParagraph> _story(WmlDocument document, String story) =>
    switch (story) {
      'header' => document.sections.single.header,
      'footer' => document.sections.single.footer,
      'comment' => document.comments.single.paragraphs,
      _ => throw ArgumentError.value(story),
    };

List<WmlParagraph> _openStory(
  WordEditorController controller,
  String story,
  List<String> text,
) {
  final paragraphs = text.map(_paragraph).toList();
  if (story == 'comment') {
    controller.document.comments.add(WmlComment(id: 7, paragraphs: paragraphs));
    controller.beginCommentEdit(7);
  } else {
    _story(controller.document, story).addAll(paragraphs);
    controller.beginHeaderFooterEdit(0, footer: story == 'footer');
  }
  controller.document.trackRevisions = true;
  return _story(controller.document, story);
}

void _closeStory(WordEditorController controller, String story) {
  if (story == 'comment') {
    controller.endCommentEdit();
  } else {
    controller.endHeaderFooterEdit();
  }
}

Iterable<XmlElement> _descendants(XmlElement root, String name) sync* {
  for (final child in root.childElements) {
    if (child.localName == name) yield child;
    yield* _descendants(child, name);
  }
}

List<String> _nativeRevisions(
  OpcPackage package,
  String partPrefix,
  String kind,
) => [
  for (final part in package.parts)
    if (part.uri.startsWith(partPrefix) && part.uri.endsWith('.xml'))
      for (final revision in _descendants(
        XmlDocument.parse(package.getPart(part.uri)!.readText()).root!,
        kind,
      ))
        revision.text,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final story in ['header', 'footer', 'comment']) {
    for (final link in [false, true]) {
      test(
        '$story tracked ${link ? 'link' : 'typing'} rejects in its own story after close and reopen',
        () {
          final controller = _controller();
          final paragraphs = _openStory(controller, story, ['Story tail']);
          controller.caret.logicalIndex = 5;
          controller.caret.collapseSelection();
          if (link) {
            controller.insertHyperlink(
              text: ' added',
              target: 'https://example.com/added',
            );
          } else {
            controller.insertText(' added');
          }
          expect(paragraphs.single.text, 'Story added tail');
          expect(
            controller.document.paragraphs.single.text,
            'Body content must stay',
          );
          expect(controller.document.revisions.single.text, ' added');
          final revision = controller.document.revisions.single;
          _closeStory(controller, story);
          final bytes = controller.saveBytes();
          final package = OpcPackage.openBytes(bytes);
          expect(_nativeRevisions(package, '/word/document', 'ins'), isEmpty);
          expect(_nativeRevisions(package, '/word/$story', 'ins'), [' added']);

          controller.rejectRevision(revision);
          expect(controller.isDirty, isTrue);
          for (var cycle = 0; cycle < 3; cycle++) {
            expect(paragraphs.single.text, 'Story tail');
            expect(
              controller.document.paragraphs.single.text,
              'Body content must stay',
            );
            expect(controller.document.revisions, isEmpty);
            controller.undo();
            expect(paragraphs.single.text, 'Story added tail');
            expect(controller.document.revisions.single, same(revision));
            controller.redo();
          }

          final reopened = WordEditorController(
            document: WordDeserializer().readBytes(bytes),
          );
          addTearDown(reopened.dispose);
          final imported = _story(reopened.document, story).single;
          expect(imported.text, 'Story added tail');
          expect(reopened.document.revisions.single.text, ' added');
          if (link) {
            expect(
              imported.inlines
                  .whereType<WmlRun>()
                  .where((run) => run.hyperlink != null)
                  .single
                  .hyperlink
                  ?.url,
              'https://example.com/added',
            );
          }
          reopened.rejectAllRevisions();
          expect(imported.text, 'Story tail');
          expect(
            reopened.document.paragraphs.single.text,
            'Body content must stay',
          );
          reopened.undo();
          expect(imported.text, 'Story added tail');
          reopened.redo();
          expect(imported.text, 'Story tail');
        },
      );
    }

    test('$story tracked backspace accepts only its own text with history', () {
      final controller = _controller();
      final paragraphs = _openStory(controller, story, ['Story tail']);
      controller.caret.logicalIndex = 5;
      controller.caret.collapseSelection();
      controller.deleteSelectionOr(backward: true);
      expect(paragraphs.single.text, 'Story tail');
      final revision = controller.document.revisions.single;
      expect(revision.text, 'y');
      expect(revision.kind, WmlRevisionKind.delete);
      _closeStory(controller, story);
      final bytes = controller.saveBytes();
      final package = OpcPackage.openBytes(bytes);
      expect(_nativeRevisions(package, '/word/document', 'del'), isEmpty);
      expect(_nativeRevisions(package, '/word/$story', 'del'), ['y']);

      controller.acceptRevision(revision);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(paragraphs.single.text, 'Stor tail');
        expect(
          controller.document.paragraphs.single.text,
          'Body content must stay',
        );
        expect(controller.document.revisions, isEmpty);
        controller.undo();
        expect(paragraphs.single.text, 'Story tail');
        expect(controller.document.revisions.single, same(revision));
        controller.redo();
      }

      final reopened = WordEditorController(
        document: WordDeserializer().readBytes(bytes),
      );
      addTearDown(reopened.dispose);
      reopened.acceptAllRevisions();
      expect(_story(reopened.document, story).single.text, 'Stor tail');
      expect(
        reopened.document.paragraphs.single.text,
        'Body content must stay',
      );
    });

    test(
      '$story tracked range keeps paragraphs and body drawings until accepted',
      () {
        final controller = _controller();
        final bodyDrawing = WmlVisual(
          visual: OfficeVisual(
            kind: OfficeVisualKind.chartColumn,
            title: 'Body chart',
          ),
        );
        controller.document.sections.single.blocks.addAll([
          bodyDrawing,
          _paragraph('Body second'),
          _paragraph('Body third'),
        ]);
        final paragraphs = _openStory(controller, story, [
          'First prefix',
          'Middle',
          'Last suffix',
        ]);
        final originals = List<WmlParagraph>.of(paragraphs);
        controller.caret
          ..selectionAnchorParagraph = 0
          ..selectionAnchor = 6
          ..paragraphIndex = 2
          ..logicalIndex = 5;
        controller.deleteSelectionOr(backward: false);
        expect(paragraphs, originals);
        expect(paragraphs.map((p) => p.text), [
          'First prefix',
          'Middle',
          'Last suffix',
        ]);
        expect(controller.document.revisions.map((r) => r.text), [
          'Last ',
          'Middle',
          'prefix',
        ]);
        expect(controller.document.visuals.single, same(bodyDrawing));
        _closeStory(controller, story);
        final bytes = controller.saveBytes();

        controller.acceptAllRevisions();
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(paragraphs, originals);
          expect(paragraphs.map((p) => p.text), ['First ', '', 'suffix']);
          expect(controller.document.paragraphs.map((p) => p.text), [
            'Body content must stay',
            'Body second',
            'Body third',
          ]);
          expect(controller.document.visuals.single, same(bodyDrawing));
          controller.undo();
          expect(paragraphs.map((p) => p.text), [
            'First prefix',
            'Middle',
            'Last suffix',
          ]);
          expect(controller.document.revisions, hasLength(3));
          controller.redo();
        }

        final reopened = WordEditorController(
          document: WordDeserializer().readBytes(bytes),
        );
        addTearDown(reopened.dispose);
        expect(reopened.document.revisions, hasLength(3));
        reopened.acceptAllRevisions();
        expect(_story(reopened.document, story).map((p) => p.text), [
          'First ',
          '',
          'suffix',
        ]);
        expect(reopened.document.paragraphs.map((p) => p.text), [
          'Body content must stay',
          'Body second',
          'Body third',
        ]);
        expect(reopened.document.visuals.single.visual.title, 'Body chart');
      },
    );
  }

  test('revision retains body target after an unrelated paragraph split', () {
    final controller = _controller();
    final target = _paragraph('Target');
    controller.document.sections.single.blocks.add(target);
    controller.document.trackRevisions = true;
    controller.relayout();
    controller.jumpToParagraph(1);
    controller.caret.logicalIndex = 6;
    controller.caret.collapseSelection();
    controller.insertText(' added');
    final revision = controller.document.revisions.single;
    controller.jumpToParagraph(0);
    controller.caret.logicalIndex = 0;
    controller.caret.collapseSelection();
    controller.insertParagraphBreak();
    controller.rejectRevision(revision);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(controller.document.paragraphs.map((p) => p.text), [
        '',
        'Body content must stay',
        'Target',
      ]);
      controller.undo();
      expect(target.text, 'Target added');
      controller.undo();
      expect(controller.document.paragraphs.map((p) => p.text), [
        'Body content must stay',
        'Target added',
      ]);
      controller.redo();
      controller.redo();
    }
  });

  testWidgets('auxiliary revisions do not paint changes over body text', (
    tester,
  ) async {
    final controller = _controller();
    _openStory(controller, 'header', ['Header']);
    controller.caret.logicalIndex = 0;
    controller.caret.collapseSelection();
    controller.insertText('New');
    _closeStory(controller, 'header');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WordCanvas(
          document: controller.document,
          laidOut: controller.documentLaidOut,
          caret: controller.caret,
        ),
      ),
    );
    bool isInsertionHighlight(Symbol method, List<dynamic> arguments) =>
        method == #drawRect &&
        (arguments[1] as Paint).color.toARGB32() == 0x3327AE60;
    expect(
      find.byType(WordCanvas),
      isNot(paints..something(isInsertionHighlight)),
    );

    controller.document.revisions.clear();
    controller.caret.logicalIndex = 0;
    controller.caret.collapseSelection();
    controller.insertText('New');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WordCanvas(
          document: controller.document,
          laidOut: controller.documentLaidOut,
          caret: controller.caret,
        ),
      ),
    );
    expect(find.byType(WordCanvas), paints..something(isInsertionHighlight));
  });
}
