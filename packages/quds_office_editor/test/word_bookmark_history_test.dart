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

({
  WordEditorController controller,
  WmlNote note,
  WmlParagraph first,
  WmlParagraph last,
})
_noteFixture({bool endnote = false}) {
  final first = WmlParagraph(
    properties: WmlParagraphProps(bookmarkName: 'NoteRange')
      ..sourceBookmarkName = 'NoteRange',
    inlines: [
      WmlBookmarkBoundary(
        id: '7',
        isStart: true,
        name: 'NoteRange',
        sourceXml:
            '<w:bookmarkStart xmlns:w="${OfficeNamespaces.w}" '
            'w:id="7" w:name="NoteRange" w:colFirst="1" w:colLast="2"/>',
      ),
      WmlRun(text: 'First'),
    ],
  );
  final last = WmlParagraph(
    inlines: [
      WmlRun(text: 'Last', properties: WmlRunProps(italic: true)),
      WmlBookmarkBoundary(id: '7', isStart: false),
    ],
  );
  final note = WmlNote(
    id: 2,
    endnote: endnote,
    addReference: false,
    paragraphs: [first, last],
  );
  final document = WmlDocument.empty(text: 'Body');
  (endnote ? document.endnotes : document.footnotes).add(note);
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return (controller: controller, note: note, first: first, last: last);
}

void _prepareBodyHistory(WordEditorController controller) {
  _at(controller, controller.document.paragraphs.single.text.length);
  controller.insertText('+');
  controller.insertText('?');
  controller.undo();
  expect(controller.document.paragraphs.single.text, 'Body+');
  expect(controller.commands.canUndo, isTrue);
  expect(controller.commands.canRedo, isTrue);
  controller.markClean();
}

(int, int, int, int) _selection(WordEditorController controller) => (
  controller.caret.paragraphIndex,
  controller.caret.logicalIndex,
  controller.caret.selectionAnchorParagraph,
  controller.caret.selectionAnchor,
);

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

  test(
    'complete native range paste remaps without flattening endpoints',
    () async {
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
      await controller.pasteFromClipboard();
      expect(paragraph.text, 'pre SELECTED postpre SELECTED post');
      expect(
        WordBookmarks.byName(controller.document, 'SelectedRange_copy')!.text,
        'SELECTED',
      );
      expect(
        WordBookmarks.byName(
          controller.document,
          'SelectedRange_copy',
        )!.start.id,
        '1',
      );
      controller.undo();
      expect(paragraph.text, 'pre SELECTED post');
      _assertNative(controller);
    },
  );

  test(
    'a partial bookmark in a later block rejects before preceding text is inserted',
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
            WmlClone.paragraph(paragraph)
              ..inlines.removeWhere(
                (inline) => inline is WmlBookmarkBoundary && !inline.isStart,
              ),
          ],
        ),
      );
      _at(controller, paragraph.text.length);
      await expectLater(controller.pasteFromClipboard(), throwsStateError);
      expect(paragraph.text, 'pre SELECTED post');
      expect(controller.document.paragraphs.single, same(paragraph));
      expect(controller.commands.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      _assertNative(controller);
    },
  );

  test('an orphan note endpoint fails before creating a history snapshot', () {
    final fixture = _noteFixture();
    final controller = fixture.controller;
    final note = fixture.note;
    _prepareBodyHistory(controller);
    controller.caret
      ..logicalIndex = 1
      ..selectionAnchor = 4;
    final selection = _selection(controller);
    final inlines = {
      for (final paragraph in note.allParagraphs)
        paragraph: List<WmlInline>.of(paragraph.inlines),
    };
    expect(
      () => controller.setNoteText(note, 'Changed first'),
      throwsUnsupportedError,
    );
    expect(note.paragraphs, [same(fixture.first), same(fixture.last)]);
    expect(controller.noteEditText(note), 'First\nLast');
    for (final entry in inlines.entries) {
      expect(entry.key.inlines, orderedEquals(entry.value));
    }
    expect(controller.document.paragraphs.single.text, 'Body+');
    expect(_selection(controller), selection);
    expect(controller.isDirty, isFalse);
    expect(controller.commands.canUndo, isTrue);
    expect(controller.commands.canRedo, isTrue);
    expect(
      WordBookmarks.byName(controller.document, 'NoteRange')!.text,
      'First\nLast',
    );

    // A rejected edit must not leave a stale pending snapshot that erases a
    // subsequent host formatting change when the next valid note edit is undone.
    fixture.first.inlines.whereType<WmlRun>().single.properties.bold = true;
    controller.setNoteText(note, 'Changed first\nLast');
    controller.commitNoteEdit(note);
    controller.undo();
    expect(controller.noteEditText(note), 'First\nLast');
    expect(
      fixture.first.inlines.whereType<WmlRun>().single.properties.bold,
      isTrue,
    );
    controller.undo();
    expect(controller.document.paragraphs.single.text, 'Body');
    expect(controller.commands.canUndo, isFalse);
  });

  test(
    'an orphan endpoint cannot commit another pending note or clear redo',
    () {
      final fixture = _noteFixture(endnote: true);
      final controller = fixture.controller;
      final pending = WmlNote(
        id: 3,
        endnote: false,
        addReference: false,
        paragraphs: [
          WmlParagraph(inlines: [WmlRun(text: 'Pending original')]),
        ],
      );
      controller.document.footnotes.add(pending);
      _prepareBodyHistory(controller);
      controller.setNoteText(pending, 'Pending edit one');
      controller.caret
        ..logicalIndex = 1
        ..selectionAnchor = 4;
      final selection = _selection(controller);
      final pendingInlines = List<WmlInline>.of(
        pending.paragraphs.single.inlines,
      );
      final firstInlines = List<WmlInline>.of(fixture.first.inlines);
      final lastInlines = List<WmlInline>.of(fixture.last.inlines);
      expect(
        () => controller.setNoteText(fixture.note, 'Changed first'),
        throwsUnsupportedError,
      );
      expect(fixture.note.paragraphs, [
        same(fixture.first),
        same(fixture.last),
      ]);
      expect(fixture.first.inlines, orderedEquals(firstInlines));
      expect(fixture.last.inlines, orderedEquals(lastInlines));
      expect(pending.paragraphs.single.inlines, orderedEquals(pendingInlines));
      expect(controller.noteEditText(fixture.note), 'First\nLast');
      expect(controller.noteEditText(pending), 'Pending edit one');
      expect(controller.document.paragraphs.single.text, 'Body+');
      expect(_selection(controller), selection);
      expect(controller.isDirty, isTrue);
      expect(controller.commands.canUndo, isTrue);
      expect(controller.commands.canRedo, isTrue);

      controller.redo();
      expect(controller.document.paragraphs.single.text, 'Body+?');
      expect(controller.commands.canRedo, isFalse);
      controller.setNoteText(pending, 'Pending edit two');
      controller.undo();
      expect(controller.noteEditText(pending), 'Pending original');
      controller.redo();
      expect(controller.noteEditText(pending), 'Pending edit two');
      controller.undo();
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Body+');
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Body');
      expect(controller.commands.canUndo, isFalse);
      expect(controller.noteEditText(fixture.note), 'First\nLast');
    },
  );

  for (final endnote in [false, true]) {
    test(
      'whole ${endnote ? 'endnote' : 'footnote'} bookmark deletion restores native ranges through history',
      () {
        final fixture = _noteFixture(endnote: endnote);
        final controller = fixture.controller;
        final note = fixture.note;
        final keep = WmlParagraph(
          inlines: [
            WmlNoteMarker(endnote: endnote, properties: WmlRunProps()),
            WmlRun(text: 'Keep'),
          ],
        );
        final control = WmlContentControlBlock(
          control: WmlContentControlData(
            xml:
                '<w:sdt xmlns:w="${OfficeNamespaces.w}">'
                '<w:sdtPr><w:id w:val="20"/></w:sdtPr>'
                '<w:sdtContent/></w:sdt>',
            sourcePartUri: endnote
                ? '/word/endnotes.xml'
                : '/word/footnotes.xml',
            relationships: const [],
          ),
          blocks: [keep, fixture.first, fixture.last],
        );
        final cell = WmlParagraph(inlines: [WmlRun(text: 'Table remains')]);
        final table = WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [cell]),
              ],
            ),
          ],
        );
        note.blocks
          ..clear()
          ..addAll([control, table]);
        expect(controller.noteEditText(note), 'Keep\nFirst\nLast');
        controller.setNoteText(note, 'Keep changed');
        controller.commitNoteEdit(note);

        for (var cycle = 0; cycle < 3; cycle++) {
          expect(note.blocks, [same(control), same(table)]);
          expect(control.blocks, [same(keep)]);
          expect(note.addReference, isFalse);
          expect(keep.inlines.whereType<WmlNoteMarker>(), hasLength(1));
          expect(controller.noteEditText(note), 'Keep changed');
          expect(
            WordBookmarks.byName(controller.document, 'NoteRange'),
            isNull,
          );
          expect(cell.text, 'Table remains');
          expect(controller.document.paragraphs.single.text, 'Body');
          final reopened = WordDeserializer().readBytes(controller.saveBytes());
          expect(WordBookmarks.byName(reopened, 'NoteRange'), isNull);
          expect(
            WordNotes.editableText(
              (endnote ? reopened.endnotes : reopened.footnotes).single,
            ),
            'Keep changed',
          );

          controller.undo();
          expect(controller.commands.canUndo, isFalse);
          expect(control.blocks, [
            same(keep),
            same(fixture.first),
            same(fixture.last),
          ]);
          expect(controller.noteEditText(note), 'Keep\nFirst\nLast');
          final range = WordBookmarks.byName(controller.document, 'NoteRange')!;
          expect(range.startParagraph, same(fixture.first));
          expect(range.endParagraph, same(fixture.last));
          expect(range.text, 'First\nLast');
          expect(
            fixture.last.inlines.whereType<WmlRun>().single.properties.italic,
            isTrue,
          );
          final restoredBytes = controller.saveBytes();
          final package = OpcPackage.openBytes(restoredBytes);
          final xml = XmlDocument.parse(
            package
                .getPart(
                  endnote ? '/word/endnotes.xml' : '/word/footnotes.xml',
                )!
                .readText(),
          ).root!;
          final start = _all(xml, 'bookmarkStart').single;
          expect(start.getAttribute('id'), '7');
          expect(start.getAttribute('name'), 'NoteRange');
          expect(start.getAttribute('colFirst'), '1');
          expect(start.getAttribute('colLast'), '2');
          expect(_all(xml, 'bookmarkEnd').single.getAttribute('id'), '7');
          expect(
            WordBookmarks.byName(
              WordDeserializer().readBytes(restoredBytes),
              'NoteRange',
            )!.text,
            'First\nLast',
          );
          controller.redo();
        }
      },
    );
  }
}
