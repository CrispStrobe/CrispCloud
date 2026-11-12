import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _date = '2026-10-01T12:30:00Z';

WordEditorController _controller([String text = 'abXYZcd']) {
  final controller = WordEditorController(
    document: WmlDocument.empty(text: text),
  );
  addTearDown(controller.dispose);
  return controller;
}

WmlRevision _pending(
  WordEditorController controller,
  WmlParagraph paragraph,
  int start,
  int end, {
  WmlRevisionKind kind = WmlRevisionKind.insert,
}) {
  final revision = WordRevisions.record(
    controller.document,
    paragraph: paragraph,
    paragraphIndex: controller.document.paragraphs.toList().indexOf(paragraph),
    kind: kind,
    start: start,
    end: end,
    text: paragraph.text.substring(start, end),
    author: 'Original reviewer',
  )..dateIso = _date;
  controller.document.trackRevisions = false;
  return revision;
}

void _expectRange(
  WmlRevision revision,
  WmlParagraph paragraph,
  int start,
  int end, [
  String text = 'XYZ',
]) {
  expect(revision.targetParagraph, same(paragraph));
  expect((revision.start, revision.end, revision.text), (start, end, text));
  expect(revision.author, 'Original reviewer');
  expect(revision.dateIso, _date);
  expect(revision.accepted, isNull);
}

void _at(WordEditorController controller, int offset, [int paragraph = 0]) {
  controller.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = offset
    ..collapseSelection();
}

WordEditorController _reopen(WordEditorController controller) {
  final bytes = controller.saveBytes();
  // Inspect native wrappers independently of the importer, so matching reader
  // and writer errors cannot make a coalesced or shifted span look correct.
  final native = <(String, String, String?, String?)>[];
  void collect(XmlElement element) {
    if (element.namespaceUri == OfficeNamespaces.w &&
        (element.localName == 'ins' || element.localName == 'del')) {
      native.add((
        element.localName,
        element.text,
        element.getAttribute('author', namespaceUri: OfficeNamespaces.w),
        element.getAttribute('date', namespaceUri: OfficeNamespaces.w),
      ));
    }
    for (final child in element.childElements) {
      collect(child);
    }
  }

  final package = OpcPackage.openBytes(bytes);
  for (final uri in package.partNames) {
    if (uri.startsWith('/word/') && uri.endsWith('.xml')) {
      final root = XmlDocument.parse(package.getPart(uri)!.readText()).root;
      if (root != null) collect(root);
    }
  }
  expect(
    native,
    unorderedEquals([
      for (final revision in controller.document.revisions)
        (
          revision.kind == WmlRevisionKind.insert ? 'ins' : 'del',
          revision.text,
          revision.author,
          revision.dateIso,
        ),
    ]),
  );
  final result = WordEditorController(
    document: WordDeserializer().readBytes(bytes),
  );
  addTearDown(result.dispose);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repeated text uses the actual edit coordinates', () {
    final controller = _controller('aaaaaa');
    final paragraph = controller.document.paragraphs.single;
    final revision = _pending(controller, paragraph, 2, 4);
    _at(controller, 0);
    controller.insertText('a');
    _expectRange(revision, paragraph, 3, 5, 'aa');
    _reopen(controller);
    controller.undo();
    _expectRange(revision, paragraph, 2, 4, 'aa');
    controller.redo();
    _expectRange(revision, paragraph, 3, 5, 'aa');
  });

  for (final deletion in [false, true]) {
    test(
      '${deletion ? 'delete' : 'insert'} inside a change preserves typing and blocks unsafe resolution',
      () {
        final controller = _controller();
        final paragraph = controller.document.paragraphs.single;
        final revision = _pending(controller, paragraph, 2, 5);
        _at(controller, 3);
        if (deletion) {
          controller.deleteSelectionOr(backward: false);
        } else {
          controller.insertText('!');
        }
        final edited = deletion ? 'abXZcd' : 'abX!YZcd';
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(paragraph.text, edited);
          expect(revision.conflict, contains('intersects'));
          expect(() => controller.rejectRevision(revision), throwsStateError);
          expect(() => controller.acceptRevision(revision), throwsStateError);
          expect(controller.saveBytes, throwsStateError);
          expect(paragraph.text, edited);
          expect(revision.accepted, isNull);
          expect(controller.document.revisions, [same(revision)]);
          controller.undo();
          expect(paragraph.text, 'abXYZcd');
          expect(revision.conflict, isNull);
          _expectRange(revision, paragraph, 2, 5);
          _reopen(controller);
          controller.redo();
        }
      },
    );
  }

  test('a split through a pending range is an undoable conflict', () {
    final controller = _controller();
    final paragraph = controller.document.paragraphs.single;
    final revision = _pending(controller, paragraph, 2, 5);
    _at(controller, 3);
    controller.insertParagraphBreak();
    expect(controller.document.paragraphs.map((p) => p.text), ['abX', 'YZcd']);
    expect(revision.conflict, contains('split'));
    expect(controller.saveBytes, throwsStateError);
    controller.undo();
    expect(controller.document.paragraphs.single, same(paragraph));
    expect(paragraph.text, 'abXYZcd');
    expect(revision.conflict, isNull);
    _expectRange(revision, paragraph, 2, 5);
    _reopen(controller);
    controller.redo();
    expect(revision.conflict, contains('split'));
  });

  test('overlapping tracked deletion restores prior attribution on undo', () {
    final controller = _controller();
    final paragraph = controller.document.paragraphs.single;
    final revision = _pending(controller, paragraph, 2, 5);
    controller.document.trackRevisions = true;
    _at(controller, 3);
    controller.deleteSelectionOr(backward: false);
    expect(paragraph.text, 'abXYZcd');
    expect(controller.document.revisions, hasLength(2));
    expect(revision.conflict, contains('overlap'));
    expect(controller.acceptAllRevisions, throwsStateError);
    expect(paragraph.text, 'abXYZcd');
    expect(controller.document.revisions, hasLength(2));
    controller.undo();
    expect(controller.document.revisions, [same(revision)]);
    expect(revision.conflict, isNull);
    _reopen(controller);
    controller.redo();
    expect(revision.conflict, contains('overlap'));
  });

  for (final scenario in [
    (at: 0, start: 4, end: 7, edited: '--abXYZcd', resolved: '--abcd'),
    (at: 2, start: 4, end: 7, edited: 'ab--XYZcd', resolved: 'ab--cd'),
    (at: 5, start: 2, end: 5, edited: 'abXYZ--cd', resolved: 'ab--cd'),
    (at: 7, start: 2, end: 5, edited: 'abXYZcd--', resolved: 'abcd--'),
  ]) {
    test('insertion at ${scenario.at} preserves the exact pending span', () {
      final controller = _controller();
      final paragraph = controller.document.paragraphs.single;
      final revision = _pending(controller, paragraph, 2, 5);
      _at(controller, scenario.at);
      controller.insertText('--');
      _expectRange(revision, paragraph, scenario.start, scenario.end);
      expect(paragraph.text, scenario.edited);
      final reopened = _reopen(controller);
      expect(reopened.document.revisions.single.text, 'XYZ');
      reopened.rejectAllRevisions();
      expect(reopened.document.paragraphs.single.text, scenario.resolved);
      controller.rejectRevision(revision);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(paragraph.text, scenario.resolved);
        controller.undo();
        expect(paragraph.text, scenario.edited);
        _expectRange(revision, paragraph, scenario.start, scenario.end);
        controller.undo();
        expect(paragraph.text, 'abXYZcd');
        _expectRange(revision, paragraph, 2, 5);
        controller.redo();
        controller.redo();
      }
    });
  }

  test('tracked prefix and prior insertion can be resolved separately', () {
    final controller = _controller();
    final paragraph = controller.document.paragraphs.single;
    final original = _pending(controller, paragraph, 2, 5);
    controller.document.trackRevisions = true;
    _at(controller, 0);
    controller.insertText('+');
    final prefix = controller.document.revisions.last;
    _expectRange(original, paragraph, 3, 6);
    expect((prefix.start, prefix.end, prefix.text), (0, 1, '+'));
    final reopened = _reopen(controller);
    expect(reopened.document.revisions.map((r) => r.text), ['+', 'XYZ']);
    reopened.rejectAllRevisions();
    expect(reopened.document.paragraphs.single.text, 'abcd');
    controller.rejectRevision(original);
    expect(paragraph.text, '+abcd');
    controller.rejectRevision(prefix);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(paragraph.text, 'abcd');
      controller.undo();
      controller.undo();
      _expectRange(original, paragraph, 3, 6);
      controller.undo();
      _expectRange(original, paragraph, 2, 5);
      expect(controller.document.revisions, [original]);
      controller.redo();
      controller.redo();
      controller.redo();
    }
  });

  test(
    'deleting an untracked prefix moves the pending span and undoes exactly',
    () {
      final controller = _controller();
      final paragraph = controller.document.paragraphs.single;
      final revision = _pending(controller, paragraph, 2, 5);
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = 2;
      controller.deleteSelectionOr(backward: false);
      expect(paragraph.text, 'XYZcd');
      _expectRange(revision, paragraph, 0, 3);
      final reopened = _reopen(controller);
      reopened.rejectAllRevisions();
      expect(reopened.document.paragraphs.single.text, 'cd');
      controller.rejectRevision(revision);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(paragraph.text, 'cd');
        controller.undo();
        _expectRange(revision, paragraph, 0, 3);
        controller.undo();
        expect(paragraph.text, 'abXYZcd');
        _expectRange(revision, paragraph, 2, 5);
        controller.redo();
        controller.redo();
      }
    },
  );

  test('accepting an earlier deletion rebases the surviving insertion', () {
    final controller = _controller('abXXcdYYef');
    final paragraph = controller.document.paragraphs.single;
    final deleted = _pending(
      controller,
      paragraph,
      2,
      4,
      kind: WmlRevisionKind.delete,
    );
    final inserted = _pending(controller, paragraph, 6, 8);
    controller.acceptRevision(deleted);
    expect(paragraph.text, 'abcdYYef');
    _expectRange(inserted, paragraph, 4, 6, 'YY');
    final reopened = _reopen(controller);
    reopened.rejectAllRevisions();
    expect(reopened.document.paragraphs.single.text, 'abcdef');
    controller.rejectRevision(inserted);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(paragraph.text, 'abcdef');
      controller.undo();
      _expectRange(inserted, paragraph, 4, 6, 'YY');
      controller.undo();
      expect(paragraph.text, 'abXXcdYYef');
      _expectRange(inserted, paragraph, 6, 8, 'YY');
      _expectRange(deleted, paragraph, 2, 4, 'XX');
      controller.redo();
      controller.redo();
    }
  });

  test(
    'character formatting and hyperlinks retain exact revision boundaries',
    () {
      final controller = _controller();
      final paragraph = controller.document.paragraphs.single;
      final revision = _pending(controller, paragraph, 2, 5);
      controller.caret
        ..selectionAnchor = 2
        ..logicalIndex = 5;
      controller.applyRunFormat((props) => props.bold = true);
      controller.insertHyperlink(
        text: '',
        target: 'https://example.com/revision',
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        _expectRange(revision, paragraph, 2, 5);
        final reopened = _reopen(controller);
        expect(reopened.document.revisions.single.text, 'XYZ');
        reopened.rejectAllRevisions();
        expect(reopened.document.paragraphs.single.text, 'abcd');
        controller.undo();
        controller.undo();
        _expectRange(revision, paragraph, 2, 5);
        controller.redo();
        controller.redo();
      }
    },
  );

  for (final scenario in [
    (
      at: 0,
      target: 1,
      start: 2,
      end: 5,
      edited: ['', 'abXYZcd'],
      resolved: ['', 'abcd'],
    ),
    (
      at: 2,
      target: 1,
      start: 0,
      end: 3,
      edited: ['ab', 'XYZcd'],
      resolved: ['ab', 'cd'],
    ),
    (
      at: 5,
      target: 0,
      start: 2,
      end: 5,
      edited: ['abXYZ', 'cd'],
      resolved: ['ab', 'cd'],
    ),
    (
      at: 7,
      target: 0,
      start: 2,
      end: 5,
      edited: ['abXYZcd', ''],
      resolved: ['abcd', ''],
    ),
  ]) {
    test('paragraph split at ${scenario.at} transfers whole pending spans', () {
      final controller = _controller();
      final original = controller.document.paragraphs.single;
      final revision = _pending(controller, original, 2, 5);
      _at(controller, scenario.at);
      controller.insertParagraphBreak();
      final target = controller.document.paragraphs.elementAt(scenario.target);
      _expectRange(revision, target, scenario.start, scenario.end);
      expect(
        controller.document.paragraphs.map((p) => p.text),
        scenario.edited,
      );
      final reopened = _reopen(controller);
      reopened.rejectAllRevisions();
      expect(
        reopened.document.paragraphs.map((p) => p.text),
        scenario.resolved,
      );
      controller.rejectRevision(revision);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(
          controller.document.paragraphs.map((p) => p.text),
          scenario.resolved,
        );
        controller.undo();
        _expectRange(revision, target, scenario.start, scenario.end);
        controller.undo();
        expect(controller.document.paragraphs.single, same(original));
        _expectRange(revision, original, 2, 5);
        controller.redo();
        controller.redo();
      }
    });
  }

  for (final header in [false, true]) {
    test(
      '${header ? 'header' : 'body'} join transfers a revision from the removed paragraph',
      () {
        final controller = _controller('ab');
        final List<WmlParagraph> paragraphs;
        if (header) {
          paragraphs = controller.document.sections.single.header;
          paragraphs.add(WmlParagraph(inlines: [WmlRun(text: 'ab')]));
          controller.beginHeaderFooterEdit(0, footer: false);
        } else {
          paragraphs = controller.document.sections.single.blocks
              .cast<WmlParagraph>();
        }
        final second = WmlParagraph(inlines: [WmlRun(text: 'XYZcd')]);
        paragraphs.add(second);
        final first = paragraphs.first;
        final revision = _pending(controller, second, 0, 3);
        _at(controller, 0, 1);
        controller.deleteSelectionOr(backward: true);
        expect(paragraphs.single.text, 'abXYZcd');
        _expectRange(revision, first, 2, 5);
        final reopened = _reopen(controller);
        reopened.rejectAllRevisions();
        expect(
          (header
                  ? reopened.document.sections.single.header
                  : reopened.document.paragraphs)
              .single
              .text,
          'abcd',
        );
        controller.rejectRevision(revision);
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(paragraphs.single.text, 'abcd');
          controller.undo();
          _expectRange(revision, first, 2, 5);
          controller.undo();
          expect(paragraphs.map((p) => p.text), ['ab', 'XYZcd']);
          _expectRange(revision, second, 0, 3);
          controller.redo();
          controller.redo();
        }
        if (header) expect(controller.document.paragraphs.single.text, 'ab');
      },
    );
  }

  test(
    'story selection joins a surviving tail revision with exact history',
    () {
      final controller = _controller('Body must stay');
      final first = WmlParagraph(inlines: [WmlRun(text: 'abQQ')]);
      final last = WmlParagraph(inlines: [WmlRun(text: 'zzXYZcd')]);
      final paragraphs = controller.document.sections.single.header
        ..addAll([first, last]);
      controller.beginHeaderFooterEdit(0, footer: false);
      final revision = _pending(controller, last, 2, 5);
      controller.caret
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 2
        ..paragraphIndex = 1
        ..logicalIndex = 2;
      controller.deleteSelectionOr(backward: false);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(paragraphs.single, same(first));
        expect(first.text, 'abXYZcd');
        _expectRange(revision, first, 2, 5);
        _reopen(controller);
        controller.undo();
        expect(paragraphs, [same(first), same(last)]);
        expect(first.text, 'abQQ');
        expect(last.text, 'zzXYZcd');
        _expectRange(revision, last, 2, 5);
        controller.redo();
      }
      expect(controller.document.paragraphs.single.text, 'Body must stay');
    },
  );

  test('removing a pending note paragraph records an undoable conflict', () {
    final controller = _controller('Body must stay');
    final first = WmlParagraph(inlines: [WmlRun(text: 'First')]);
    final last = WmlParagraph(inlines: [WmlRun(text: 'abXYZcd')]);
    final note = WmlNote(
      id: 1,
      endnote: false,
      paragraphs: [first, last],
      addReference: false,
    );
    controller.document.footnotes.add(note);
    final revision = _pending(controller, last, 2, 5);
    controller.setNoteText(note, 'First');
    controller.commitNoteEdit(note);
    expect(note.paragraphs.single, same(first));
    expect(revision.conflict, contains('removed'));
    expect(controller.saveBytes, throwsStateError);
    controller.undo();
    expect(note.paragraphs, [same(first), same(last)]);
    expect(revision.conflict, isNull);
    _expectRange(revision, last, 2, 5);
    _reopen(controller);
    controller.redo();
    expect(revision.conflict, contains('removed'));
  });

  test(
    'note history preserves rich marker order, links, tables and revision targets',
    () {
      final controller = _controller('Body must stay');
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(text: 'ab'),
          WmlNoteMarker(
            endnote: false,
          properties: WmlRunProps(italic: true, color: '123456'),
          ),
          WmlRun(
            text: 'XYZ',
            properties: WmlRunProps(bold: true),
            hyperlink: WmlHyperlink.fromTarget('https://example.com/note'),
          ),
          WmlRun(text: 'cd'),
        ],
      );
      final cell = WmlParagraph(inlines: [WmlRun(text: 'Cell remains')]);
      final table = WmlTable(
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [cell]),
            ],
          ),
        ],
      );
      final note = WmlNote(
        id: 1,
        endnote: false,
        blocks: [paragraph, table],
        addReference: false,
      );
      controller.document.footnotes.add(note);
      final revision = _pending(controller, paragraph, 2, 5);
      void expectRich() {
        expect(note.blocks, [same(paragraph), same(table)]);
        expect(table.rows.single.cells.single.blocks.single, same(cell));
        expect(cell.text, 'Cell remains');
        final marker = paragraph.inlines.whereType<WmlNoteMarker>().single;
        expect(marker.properties.italic, isTrue);
        expect(marker.properties.color, '123456');
        final inserted = paragraph.inlines.whereType<WmlRun>().singleWhere(
          (run) => run.text == 'XYZ',
        );
        expect(inserted.properties.bold, isTrue);
        expect(inserted.hyperlink?.url, 'https://example.com/note');
        expect(
          paragraph.inlines.indexOf(marker),
          lessThan(paragraph.inlines.indexOf(inserted)),
        );
      }

      controller.setNoteText(note, '--abXYZcd');
      controller.commitNoteEdit(note);
      for (var cycle = 0; cycle < 3; cycle++) {
        expectRich();
        _expectRange(revision, paragraph, 4, 7);
        final reopened = _reopen(controller);
        final reopenedNote = reopened.document.footnotes.single;
        expect(
          reopenedNote.allParagraphs.first.inlines.whereType<WmlNoteMarker>(),
          hasLength(1),
        );
        reopened.rejectAllRevisions();
        expect(reopenedNote.paragraphs.first.text, '--abcd');
        controller.undo();
        expectRich();
        _expectRange(revision, paragraph, 2, 5);
        expect(paragraph.text, 'abXYZcd');
        controller.redo();
      }
    },
  );

  test(
    'note prefix edits preserve pending revision identity through history',
    () {
      final controller = _controller('Body must stay');
      final paragraph = WmlParagraph(inlines: [WmlRun(text: 'abXYZcd')]);
      final note = WmlNote(
        id: 1,
        endnote: false,
        paragraphs: [paragraph],
        addReference: false,
      );
      controller.document.footnotes.add(note);
      final revision = _pending(controller, paragraph, 2, 5);
      controller.setNoteText(note, '--abXYZcd');
      controller.commitNoteEdit(note);
      _expectRange(revision, paragraph, 4, 7);
      expect(note.paragraphs.single, same(paragraph));
      final reopened = _reopen(controller);
      reopened.rejectAllRevisions();
      expect(reopened.document.footnotes.single.text, '--abcd');
      controller.rejectRevision(revision);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(note.text, '--abcd');
        expect(controller.document.paragraphs.single.text, 'Body must stay');
        controller.undo();
        _expectRange(revision, paragraph, 4, 7);
        controller.undo();
        expect(note.paragraphs.single, same(paragraph));
        expect(note.text, 'abXYZcd');
        _expectRange(revision, paragraph, 2, 5);
        controller.redo();
        controller.redo();
      }
    },
  );
}
