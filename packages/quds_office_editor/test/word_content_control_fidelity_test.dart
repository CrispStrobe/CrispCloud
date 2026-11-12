import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController source() => WordEditorController.fromBytes(
  File(
    '../quds_office_engine/test/fixtures/fidelity/content-controls.docx',
  ).readAsBytesSync(),
);

Iterable<XmlElement> elements(XmlElement root, String name) sync* {
  if (root.localName == name && root.namespaceUri == OfficeNamespaces.w) {
    yield root;
  }
  for (final child in root.childElements) {
    yield* elements(child, name);
  }
}

XmlElement control(OpcPackage package, String id) {
  final root = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
  return elements(root, 'sdt').singleWhere(
    (node) =>
        node.firstChild('sdtPr')?.firstChild('id')?.getAttribute('val') == id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'block SDT paragraph split and inside edit survive undo redo and three saves',
    () async {
      final editor = source();
      addTearDown(editor.dispose);
      editor.jumpToParagraph(2);
      editor.caret.logicalIndex = 7;
      editor.caret.collapseSelection();
      editor.insertParagraphBreak();
      expect(
        editor.document.paragraphs.map((p) => p.text).toList().sublist(2, 4),
        ['Nested ', 'Beta'],
      );
      editor.undo();
      expect(editor.document.paragraphs.elementAt(2).text, 'Nested Beta');
      editor.redo();
      editor.jumpToParagraph(3);
      editor.caret.logicalIndex = 2;
      editor.caret.collapseSelection();
      editor.insertText(' edited ');
      expect(editor.document.paragraphs.elementAt(3).text, 'Be edited ta');
      editor.undo();
      expect(editor.document.paragraphs.elementAt(3).text, 'Beta');
      editor.redo();
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = await editor.saveBytesAsync();
        final package = OpcPackage.openBytes(bytes);
        final nested = control(package, '102');
        expect(
          nested.firstChild('sdtPr')!.firstChild('alias')!.getAttribute('val'),
          'Nested block',
        );
        expect(
          nested
              .firstChild('sdtEndPr')!
              .firstChild('rPr')!
              .firstChild('color')!
              .getAttribute('val'),
          '4488AA',
        );
        final paragraphs = nested.firstChild('sdtContent')!.childrenNamed('p');
        expect(paragraphs, hasLength(2));
        expect(
          paragraphs.map((p) => elements(p, 't').map((t) => t.text).join()),
          ['Nested ', 'Be edited ta'],
        );
        final output = File(
          'build/fidelity-content-controls/editor-controls-$cycle.docx',
        );
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes);
        editor.loadBytes(bytes);
        expect(editor.document.paragraphs.elementAt(3).text, 'Be edited ta');
      }
    },
  );

  test(
    'inline SDT split rejects before mutating document or undo history',
    () async {
      final editor = source();
      addTearDown(editor.dispose);
      editor.jumpToParagraph(1);
      editor.caret.logicalIndex = 11;
      editor.caret.collapseSelection();
      final before = editor.document.paragraphs.map((p) => p.text).toList();
      expect(editor.canUndo, isFalse);
      expect(editor.insertParagraphBreak, throwsArgumentError);
      expect(editor.canUndo, isFalse);
      expect(editor.document.paragraphs.map((p) => p.text), before);
      final saved = control(
        OpcPackage.openBytes(await editor.saveBytesAsync()),
        '201',
      );
      expect(
        elements(
          saved.firstChild('sdtContent')!,
          't',
        ).map((t) => t.text).join(),
        'Alpha',
      );
    },
  );
}
