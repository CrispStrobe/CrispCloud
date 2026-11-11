import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

List<XmlElement> _elements(XmlElement root, String localName) => [
  for (final child in root.childElements) ...[
    if (child.localName == localName) child,
    ..._elements(child, localName),
  ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearing an imported style list survives history and reopen', () async {
    final controller = WordEditorController.fromBytes(
      File(
        '../quds_office_engine/test/fixtures/fidelity/word.docx',
      ).readAsBytesSync(),
    );
    addTearDown(controller.dispose);
    controller.jumpToParagraph(3);
    expect(controller.document.paragraphs.elementAt(3).properties.numId, 5);
    controller.toggleList(numbered: true);
    expect(
      controller.document.paragraphs.elementAt(3).properties.numId,
      isNull,
    );
    expect(
      controller.document.paragraphs
          .elementAt(3)
          .properties
          .numberingSuppressed,
      isTrue,
    );
    controller.undo();
    expect(controller.document.paragraphs.elementAt(3).properties.numId, 5);
    expect(
      controller.document.paragraphs
          .elementAt(3)
          .properties
          .numberingSuppressed,
      isFalse,
    );
    controller.redo();
    var bytes = await controller.saveBytesAsync();
    for (var cycle = 0; cycle < 3; cycle++) {
      final document = WordDeserializer().readBytes(bytes);
      final properties = document.paragraphs.elementAt(3).properties;
      expect(properties.styleId, 'ListCustom');
      expect(properties.numId, isNull);
      expect(properties.listLabel, isNull);
      expect(properties.numberingSuppressed, isTrue);
      bytes = await OfficeIsolateSave.word(document);
    }
    controller.loadBytes(bytes);
    controller.jumpToParagraph(3);
    controller.toggleList(numbered: true);
    expect(
      controller.document.paragraphs.elementAt(3).properties.numId,
      greaterThan(0),
    );
    expect(
      controller.document.paragraphs
          .elementAt(3)
          .properties
          .numberingSuppressed,
      isFalse,
    );
    final reapplied = WordDeserializer().readBytes(
      await controller.saveBytesAsync(),
    );
    expect(reapplied.paragraphs.elementAt(3).properties.listLabel, isNotNull);
  });

  test(
    'heading paragraph break keeps distinct bookmarks through undo redo and save',
    () async {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'Alpha Beta'),
      );
      addTearDown(controller.dispose);
      controller.applyHeading(2);
      final original =
          controller.document.paragraphs.single.properties.bookmarkName;
      controller.caret.logicalIndex = 5;
      controller.insertParagraphBreak();
      expect(
        controller.document.paragraphs.map((p) => p.properties.bookmarkName),
        [original, null],
      );
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Alpha Beta');
      expect(
        controller.document.paragraphs.single.properties.bookmarkName,
        original,
      );
      controller.redo();
      expect(controller.document.paragraphs.map((p) => p.text), [
        'Alpha',
        ' Beta',
      ]);
      var bytes = await controller.saveBytesAsync();
      for (var cycle = 0; cycle < 3; cycle++) {
        final package = OpcPackage.openBytes(bytes);
        final root = XmlDocument.parse(
          package.getPart('/word/document.xml')!.readText(),
        ).root!;
        final starts = _elements(root, 'bookmarkStart');
        final ends = _elements(root, 'bookmarkEnd');
        // Redo performs a full relayout, which assigns a new bookmark to the
        // second heading. The source heading's anchor must remain unique.
        expect(starts, hasLength(2));
        expect(ends, hasLength(2));
        expect(starts.map((node) => node.getAttribute('name')), [
          original,
          '_Heading2_Beta',
        ]);
        expect(
          starts.map((node) => node.getAttribute('id')).toSet(),
          hasLength(2),
        );
        expect(
          starts.map((node) => node.getAttribute('id')),
          ends.map((node) => node.getAttribute('id')),
        );
        final document = WordDeserializer().readBytes(bytes);
        expect(document.paragraphs.map((p) => p.properties.headingLevel), [
          2,
          2,
        ]);
        bytes = await OfficeIsolateSave.word(document);
      }
    },
  );

  test(
    'paragraph break continues a restarted list and undo retains its restart',
    () async {
      final document = WmlDocument.empty(text: 'First second');
      final paragraph = document.paragraphs.single;
      WordLists.applyLevel(paragraph, numbered: true, document: document);
      WordLists.restart(paragraph, at: 4);
      final controller = WordEditorController(document: document);
      addTearDown(controller.dispose);
      controller.caret.logicalIndex = 5;
      controller.insertParagraphBreak();
      expect(document.paragraphs.map((p) => p.properties.listRestart), [
        4,
        null,
      ]);
      controller.undo();
      expect(document.paragraphs.single.text, 'First second');
      expect(document.paragraphs.single.properties.listRestart, 4);
      controller.redo();
      var bytes = await controller.saveBytesAsync();
      for (var cycle = 0; cycle < 3; cycle++) {
        final reopened = WordDeserializer().readBytes(bytes);
        expect(reopened.paragraphs.map((p) => p.properties.listLabel?.trim()), [
          '4.',
          '5.',
        ]);
        expect(
          reopened.paragraphs.map((p) => p.properties.numId).toSet(),
          hasLength(1),
        );
        expect(reopened.paragraphs.map((p) => p.text), ['First', ' second']);
        bytes = await OfficeIsolateSave.word(reopened);
      }
    },
  );
}
