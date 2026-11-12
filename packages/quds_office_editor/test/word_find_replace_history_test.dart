import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return controller;
}

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

List<XmlElement> _all(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.namespaceUri == OfficeNamespaces.w && child.localName == name)
      child,
    ..._all(child, name),
  ],
];

final _staleHitChanges = <String, void Function(WmlDocument, WmlParagraph)>{
  'atomic field shape': (document, paragraph) {
    // Keep the cache stable during the normal field refresh on history.
    paragraph.inlines.whereType<WmlRun>().single
      ..fieldInstruction = ' REF entire '
      ..fieldLocked = true;
  },
  'content-control shape': (document, paragraph) {
    final control = WmlContentControlData(
      xml:
          '<w:sdt xmlns:w="${OfficeNamespaces.w}">'
          '<w:sdtContent/></w:sdt>',
      sourcePartUri: '/word/document.xml',
      relationships: const [],
    );
    paragraph.inlines.insert(
      0,
      WmlContentControlBoundary(control: control, start: true),
    );
    paragraph.inlines.add(
      WmlContentControlBoundary(control: control, start: false),
    );
  },
  'bookmark shape': (document, paragraph) {
    paragraph.inlines.insert(
      0,
      WmlBookmarkBoundary(id: '1', isStart: true, name: 'Target'),
    );
    paragraph.inlines.add(WmlBookmarkBoundary(id: '1', isStart: false));
  },
  'an identical paragraph inserted at the hit index': (document, paragraph) {
    document.sections.single.blocks.insert(1, _paragraph(paragraph.text));
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a later guarded replace-all match leaves earlier text and history untouched',
    () {
      final first = _paragraph('bX safe');
      final control = WmlContentControlData(
        xml: '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtContent/></w:sdt>',
        sourcePartUri: '/word/document.xml',
        relationships: const [],
      );
      final last = WmlParagraph(
        inlines: [
          WmlRun(text: 'ab'),
          WmlContentControlBoundary(control: control, start: true),
          WmlRun(text: 'XYZ'),
          WmlContentControlBoundary(control: control, start: false),
          WmlRun(text: 'cd'),
        ],
      );
      final controller = _controller(
        WmlDocument(
          sections: [
            WmlSection(blocks: [first, last]),
          ],
        ),
      );
      expect(
        () => controller.replaceAll(
          const OfficeFindOptions(query: 'bX', replaceWith: '!'),
        ),
        throwsUnsupportedError,
      );
      expect(first.text, 'bX safe');
      expect(last.text, 'abXYZcd');
      expect(controller.commands.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      controller.caret
        ..paragraphIndex = 0
        ..logicalIndex = 0
        ..collapseSelection();
      controller.insertText('+');
      expect(first.text, '+bX safe');
      controller.undo();
      expect(first.text, 'bX safe');
      expect(controller.commands.canUndo, isFalse);
    },
  );

  test(
    'multi-match replacement preserves native ranges and one-step rich history',
    () {
      final first = WmlParagraph(
        inlines: [
          WmlRun(text: 'old ', properties: WmlRunProps(italic: true)),
          WmlBookmarkBoundary(id: '5', isStart: true, name: 'SelectedWord'),
          WmlRun(text: 'old', properties: WmlRunProps(bold: true)),
          WmlBookmarkBoundary(id: '5', isStart: false),
          WmlRun(text: ' '),
          WmlRun(
            text: '1',
            noteRefId: 1,
            properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
          ),
          WmlRun(text: ' XYZ old'),
        ],
      );
      final last = _paragraph('old second');
      final note = WmlNote(
        id: 1,
        endnote: false,
        paragraphs: [_paragraph('Note body remains')],
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [first, last]),
        ],
      );
      document.footnotes.add(note);
      final start = first.text.indexOf('XYZ');
      final revision = WordRevisions.record(
        document,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        paragraph: first,
        start: start,
        end: start + 3,
        text: 'XYZ',
        author: 'Original reviewer',
      )..dateIso = '2026-10-01T12:30:00Z';
      document.trackRevisions = false;
      final controller = _controller(document);
      expect(
        controller.applyReplace(
          const OfficeFindOptions(query: 'old', replaceWith: 'newer'),
        ),
        4,
      );
      expect(controller.isDirty, isTrue);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(document.paragraphs, [same(first), same(last)]);
        expect(first.text, 'newer newer 1 XYZ newer');
        expect(last.text, 'newer second');
        expect(WordBookmarks.byName(document, 'SelectedWord')!.text, 'newer');
        expect((revision.start, revision.end), (start + 4, start + 7));
        expect(revision.targetParagraph, same(first));
        expect(revision.text, 'XYZ');
        expect(revision.author, 'Original reviewer');
        expect(revision.dateIso, '2026-10-01T12:30:00Z');
        expect(revision.conflict, isNull);
        expect(document.footnotes.single, same(note));
        expect(note.text, 'Note body remains');
        final marker = first.inlines.whereType<WmlRun>().singleWhere(
          (run) => run.noteRefId != null,
        );
        expect(marker.noteRefId, 1);
        expect(marker.properties.vertAlign, WmlVertAlign.superscript);
        final bytes = controller.saveBytes();
        final package = OpcPackage.openBytes(bytes);
        final xml = XmlDocument.parse(
          package.getPart('/word/document.xml')!.readText(),
        ).root!;
        expect(_all(xml, 'bookmarkStart').single.getAttribute('id'), '5');
        expect(_all(xml, 'bookmarkEnd').single.getAttribute('id'), '5');
        expect(_all(xml, 'footnoteReference').single.getAttribute('id'), '1');
        expect(_all(xml, 'ins').single.text, 'XYZ');
        final reopened = WordDeserializer().readBytes(bytes);
        expect(WordBookmarks.byName(reopened, 'SelectedWord')!.text, 'newer');
        WordRevisions.rejectAll(reopened);
        expect(reopened.paragraphs.first.text, 'newer newer 1  newer');
        controller.undo();
        expect(controller.commands.canUndo, isFalse);
        expect(first.text, 'old old 1 XYZ old');
        expect(last.text, 'old second');
        expect(document.revisions.single, same(revision));
        expect((revision.start, revision.end), (start, start + 3));
        expect(revision.accepted, isNull);
        expect(WordBookmarks.byName(document, 'SelectedWord')!.text, 'old');
        final runs = first.inlines.whereType<WmlRun>().toList();
        expect(runs.first.properties.italic, isTrue);
        expect(runs[1].properties.bold, isTrue);
        controller.redo();
      }
    },
  );

  test('replace-current records one stable paragraph target', () {
    final first = _paragraph('old first');
    final last = _paragraph('old last');
    final controller = _controller(
      WmlDocument(
        sections: [
          WmlSection(blocks: [first, last]),
        ],
      ),
    );
    const options = OfficeFindOptions(query: 'old', replaceWith: 'new');
    final hit = controller.collectFindHits(options).last;
    expect(controller.applyReplace(options, only: hit), 1);
    expect(first.text, 'old first');
    expect(last.text, 'new last');
    controller.caret
      ..paragraphIndex = 0
      ..logicalIndex = 0
      ..collapseSelection();
    controller.undo();
    expect(last.text, 'old last');
    controller.redo();
    expect(first.text, 'old first');
    expect(last.text, 'new last');
  });

  for (final change in _staleHitChanges.entries) {
    test(
      'stale ${change.key} preserves contents, selection and both history stacks',
      () {
        final history = _paragraph('History');
        final target = _paragraph('foo bar baz');
        final document = WmlDocument(
          sections: [
            WmlSection(blocks: [history, target]),
          ],
        );
        final controller = _controller(document);
        controller.caret
          ..logicalIndex = history.text.length
          ..collapseSelection();
        controller.insertText('+');
        controller.insertText('?');
        controller.undo();
        expect(history.text, 'History+');
        expect(controller.commands.canUndo, isTrue);
        expect(controller.commands.canRedo, isTrue);
        controller.markClean();

        const options = OfficeFindOptions(query: 'bar', replaceWith: 'X');
        final hit = controller.collectFindHits(options).single;
        change.value(document, target);
        final paragraphs = document.paragraphs.toList();
        final targetIndex = paragraphs.indexOf(target);
        controller.caret
          ..paragraphIndex = targetIndex
          ..logicalIndex = 3
          ..selectionAnchorParagraph = targetIndex
          ..selectionAnchor = 7;
        final selection = (
          controller.caret.paragraphIndex,
          controller.caret.logicalIndex,
          controller.caret.selectionAnchorParagraph,
          controller.caret.selectionAnchor,
        );
        final inlines = {
          for (final paragraph in paragraphs)
            paragraph: List<WmlInline>.of(paragraph.inlines),
        };
        final texts = paragraphs.map((paragraph) => paragraph.text).toList();

        expect(
          () => controller.applyReplace(options, only: hit),
          throwsStateError,
        );
        expect(document.paragraphs, orderedEquals(paragraphs));
        expect(document.paragraphs.map((paragraph) => paragraph.text), texts);
        for (final entry in inlines.entries) {
          expect(entry.key.inlines, orderedEquals(entry.value));
        }
        expect((
          controller.caret.paragraphIndex,
          controller.caret.logicalIndex,
          controller.caret.selectionAnchorParagraph,
          controller.caret.selectionAnchor,
        ), selection);
        expect(controller.isDirty, isFalse);
        expect(controller.commands.canUndo, isTrue);
        expect(controller.commands.canRedo, isTrue);

        controller.redo();
        expect(history.text, 'History+?');
        expect(controller.commands.canRedo, isFalse);
        controller.undo();
        expect(history.text, 'History+');
        controller.undo();
        expect(history.text, 'History');
        expect(controller.commands.canUndo, isFalse);
        expect(target.text, 'foo bar baz');
        expect(target.inlines, orderedEquals(inlines[target]!));
      },
    );
  }

  test(
    'replacement inside a pending revision has an undoable attribution conflict',
    () {
      final document = WmlDocument.empty(text: 'abXYZcd');
      final paragraph = document.paragraphs.single;
      final revision = WordRevisions.record(
        document,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        start: 2,
        end: 5,
        text: 'XYZ',
      );
      document.trackRevisions = false;
      final controller = _controller(document);
      expect(
        controller.applyReplace(
          const OfficeFindOptions(query: 'XYZ', replaceWith: 'changed'),
        ),
        1,
      );
      expect(paragraph.text, 'abchangedcd');
      expect(revision.conflict, contains('intersects'));
      expect(controller.saveBytes, throwsStateError);
      controller.undo();
      expect(paragraph.text, 'abXYZcd');
      expect(revision.conflict, isNull);
      expect(document.revisions.single, same(revision));
      expect((revision.start, revision.end, revision.text), (2, 5, 'XYZ'));
      controller.redo();
      expect(paragraph.text, 'abchangedcd');
      expect(revision.conflict, contains('intersects'));
    },
  );
}
