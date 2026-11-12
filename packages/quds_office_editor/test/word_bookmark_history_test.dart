import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller({bool empty = false}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
        '<w:r><w:t xml:space="preserve">pre </w:t></w:r>'
        '<w:bookmarkStart w:id="7" w:name="SelectedRange" w:colFirst="1" w:colLast="2"/>'
        '${empty ? '' : '<w:r><w:t>SELECTED</w:t></w:r>'}'
        '<w:bookmarkEnd w:id="7"/>'
        '<w:r><w:t xml:space="preserve"> post</w:t></w:r>'
        '</w:p><w:sectPr/></w:body></w:document>',
      );
  final controller = WordEditorController(
    document: WordDeserializer().read(package),
  );
  addTearDown(controller.dispose);
  return controller;
}

void _at(WordEditorController controller, int offset, [int paragraph = 0]) {
  controller.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = offset
    ..collapseSelection();
}

List<XmlElement> _all(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.namespaceUri == OfficeNamespaces.w && child.localName == name)
      child,
    ..._all(child, name),
  ],
];

void _assertNative(WordEditorController controller) {
  final bytes = controller.saveBytes();
  final package = OpcPackage.openBytes(bytes);
  final root = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
  final start = _all(root, 'bookmarkStart').single;
  final end = _all(root, 'bookmarkEnd').single;
  expect(start.getAttribute('id'), '7');
  expect(end.getAttribute('id'), '7');
  expect(start.getAttribute('name'), 'SelectedRange');
  expect(start.getAttribute('colFirst'), '1');
  expect(start.getAttribute('colLast'), '2');
  final reopened = WordDeserializer().readBytes(bytes);
  final before = WordBookmarks.byName(controller.document, 'SelectedRange')!;
  final after = WordBookmarks.byName(reopened, 'SelectedRange')!;
  expect(after.text, before.text);
  expect(
    (after.startOffset, after.endOffset),
    (before.startOffset, before.endOffset),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final offset in [4, 8, 12]) {
    test(
      'paragraph split at $offset preserves bookmark endpoints exactly once',
      () {
        final controller = _controller();
        final original = controller.document.paragraphs.single;
        _at(controller, offset);
        controller.insertParagraphBreak();
        final tail = controller.document.paragraphs.last;
        for (var cycle = 0; cycle < 3; cycle++) {
          final range = WordBookmarks.byName(
            controller.document,
            'SelectedRange',
          )!;
          expect(range.start.id, '7');
          expect(range.end.id, '7');
          expect(range.text, offset == 8 ? 'SELE\nCTED' : 'SELECTED');
          expect(range.startParagraph, same(offset == 4 ? tail : original));
          expect(range.endParagraph, same(offset == 12 ? original : tail));
          expect(
            controller.document.paragraphs
                .expand((p) => p.inlines)
                .whereType<WmlBookmarkBoundary>(),
            hasLength(2),
          );
          _assertNative(controller);
          controller.undo();
          expect(controller.document.paragraphs.single, same(original));
          expect(original.text, 'pre SELECTED post');
          expect(
            WordBookmarks.byName(controller.document, 'SelectedRange')!.text,
            'SELECTED',
          );
          _assertNative(controller);
          controller.redo();
        }
      },
    );
  }

  test('an empty bookmark pair moves together to the new paragraph', () {
    final controller = _controller(empty: true);
    final original = controller.document.paragraphs.single;
    _at(controller, 4);
    controller.insertParagraphBreak();
    final tail = controller.document.paragraphs.last;
    for (var cycle = 0; cycle < 3; cycle++) {
      final range = WordBookmarks.byName(controller.document, 'SelectedRange')!;
      expect(range.text, '');
      expect(range.startParagraph, same(tail));
      expect(range.endParagraph, same(tail));
      expect((range.startOffset, range.endOffset), (0, 0));
      expect(original.inlines.whereType<WmlBookmarkBoundary>(), isEmpty);
      _assertNative(controller);
      controller.undo();
      expect(controller.document.paragraphs.single, same(original));
      expect(original.inlines.whereType<WmlBookmarkBoundary>(), hasLength(2));
      controller.redo();
    }
  });

  test(
    'joining a split bookmark restores its single-paragraph native range',
    () {
      final controller = _controller();
      final original = controller.document.paragraphs.single;
      _at(controller, 8);
      controller.insertParagraphBreak();
      final tail = controller.document.paragraphs.last;
      _at(controller, 0, 1);
      controller.deleteSelectionOr(backward: true);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(controller.document.paragraphs.single, same(original));
        expect(
          WordBookmarks.byName(controller.document, 'SelectedRange')!.text,
          'SELECTED',
        );
        _assertNative(controller);
        controller.undo();
        expect(controller.document.paragraphs, [same(original), same(tail)]);
        expect(
          WordBookmarks.byName(controller.document, 'SelectedRange')!.text,
          'SELE\nCTED',
        );
        controller.redo();
      }
    },
  );

  test('native range paste cannot silently flatten its endpoints', () async {
    OfficeClipboard.instance.useSystem = false;
    addTearDown(() {
      OfficeClipboard.instance.clear();
      OfficeClipboard.instance.useSystem = true;
    });
    final controller = _controller();
    final paragraph = controller.document.paragraphs.single;
    final copy = WmlClone.paragraph(paragraph);
    await OfficeClipboard.instance.write(
      OfficeClipboardPayload(
        kind: OfficeClipboardKind.richText,
        plain: copy.text,
        wordBlocks: [copy],
      ),
    );
    _at(controller, paragraph.text.length);
    await expectLater(controller.pasteFromClipboard(), throwsUnsupportedError);
    expect(paragraph.text, 'pre SELECTED post');
    expect(controller.commands.canUndo, isFalse);
    _assertNative(controller);
  });

  test(
    'a copied bookmark in a later block rejects before preceding text is inserted',
    () async {
      OfficeClipboard.instance.useSystem = false;
      addTearDown(() {
        OfficeClipboard.instance.clear();
        OfficeClipboard.instance.useSystem = true;
      });
      final controller = _controller();
      final paragraph = controller.document.paragraphs.single;
      await OfficeClipboard.instance.write(
        OfficeClipboardPayload(
          kind: OfficeClipboardKind.richText,
          plain: 'Inserted prefix\n${paragraph.text}',
          wordBlocks: [
            WmlParagraph(inlines: [WmlRun(text: 'Inserted prefix')]),
            WmlClone.paragraph(paragraph),
          ],
        ),
      );
      _at(controller, paragraph.text.length);
      await expectLater(
        controller.pasteFromClipboard(),
        throwsUnsupportedError,
      );
      expect(paragraph.text, 'pre SELECTED post');
      expect(controller.document.paragraphs.single, same(paragraph));
      expect(controller.commands.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      _assertNative(controller);
    },
  );
}
