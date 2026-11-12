import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _source() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        File(
          '../quds_office_engine/test/fixtures/fidelity/bookmark_copy.xml',
        ).readAsStringSync(),
      );
  final controller = WordEditorController(
    document: WordDeserializer().read(package),
  );
  addTearDown(controller.dispose);
  return controller;
}

void _at(WordEditorController editor, int paragraph, int offset) {
  editor.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = offset
    ..collapseSelection();
}

Future<void> _copy(WordEditorController editor) async {
  editor.caret
    ..paragraphIndex = 1
    ..logicalIndex = editor.document.paragraphs.elementAt(1).text.length
    ..selectionAnchorParagraph = 0
    ..selectionAnchor = 0;
  await editor.copyToClipboard();
}

Map<String, String> _identities(WmlDocument document) => {
  for (final range in WordBookmarks.ranges(document))
    range.name: range.start.id,
};

Map<String, String> _parts(WmlDocument document) => {
  for (final part in document.package!.parts)
    part.uri: base64Encode(part.readBytes()),
};

const _original = {
  'Alpha': '000',
  'Overlap': '5',
  'Cross': '6',
  'Empty': '7',
  'Alpha_copy': '1',
  'Alpha_copy2': '2',
};
const _once = {
  ..._original,
  'Alpha_copy3': '3',
  'Overlap_copy': '4',
  'Cross_copy': '8',
  'Empty_copy': '9',
};

void _checkCopy(WmlDocument document) {
  expect(_identities(document), _once);
  for (final pair in const {
    'Alpha_copy3': 'Alpha',
    'Overlap_copy': 'Overlap',
    'Cross_copy': 'Cross',
    'Empty_copy': 'Empty',
  }.entries) {
    final original = WordBookmarks.byName(document, pair.value)!;
    final copied = WordBookmarks.byName(document, pair.key)!;
    expect(copied.text, original.text);
    expect(copied.startOffset, original.startOffset);
    expect(copied.endOffset, original.endOffset);
  }
  expect(WordBookmarks.byName(document, 'Alpha_copy3')!.text, 'A😀B');
  expect(WordBookmarks.byName(document, 'Overlap_copy')!.text, 'BCTail\nHead');
  expect(WordBookmarks.byName(document, 'Cross_copy')!.text, 'Tail\nHead End');
  expect(WordBookmarks.byName(document, 'Empty_copy')!.text, '');
  final copiedFirst = document.paragraphs.elementAt(3);
  expect(copiedFirst.properties.bookmarkName, 'Alpha_copy3');
  expect(copiedFirst.properties.sourceBookmarkName, 'Alpha_copy3');
  expect(WordBookmarks.generatedIds(document), isEmpty);
  final linked = document.paragraphs.last.inlines.whereType<WmlRun>();
  expect(
    linked.singleWhere((run) => run.text == 'Jump').hyperlink?.anchor,
    'Alpha',
  );
  expect(
    linked.singleWhere((run) => run.fieldInstruction != null).fieldInstruction,
    contains('REF Alpha'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => OfficeClipboard.instance.useSystem = false);
  tearDown(() {
    OfficeClipboard.instance.clear();
    OfficeClipboard.instance.useSystem = true;
  });

  test(
    'complete native bookmark copy keeps ranges, history and three exports',
    () async {
      final editor = _source();
      final expected = File(
        'build/fidelity-bookmark-copy/copied-expected.docx',
      );
      expected.parent.createSync(recursive: true);
      File(
        '../quds_office_engine/test/fixtures/fidelity/bookmark_copy_expected.docx',
      ).copySync(expected.path);
      final originals = editor.document.paragraphs.toList();
      await _copy(editor);
      final payload = OfficeClipboard.instance.local!;
      _at(editor, 3, 0);
      await editor.pasteFromClipboard();
      _checkCopy(editor.document);
      final copied = editor.document.paragraphs.last;
      expect(editor.document.paragraphs, hasLength(5));
      editor.undo();
      expect(editor.document.paragraphs, orderedEquals(originals));
      expect(_identities(editor.document), _original);
      editor.redo();
      expect(editor.document.paragraphs.last, same(copied));
      _checkCopy(editor.document);
      expect(
        _identities(
          WmlDocument(sections: [WmlSection(blocks: payload.wordBlocks)]),
        ),
        {'Alpha': '000', 'Overlap': '5', 'Cross': '6', 'Empty': '7'},
      );
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = await editor.saveBytesAsync();
        final output = File('build/fidelity-bookmark-copy/editor-$cycle.docx');
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes);
        editor.loadBytes(bytes);
        _checkCopy(editor.document);
      }
    },
  );

  test(
    'pasting the same payload twice allocates a fresh complete set',
    () async {
      final editor = _source();
      await _copy(editor);
      _at(editor, 3, 0);
      await editor.pasteFromClipboard();
      editor.insertParagraphBreak();
      await editor.pasteFromClipboard();
      expect(_identities(editor.document), {
        ..._once,
        'Alpha_copy4': '10',
        'Overlap_copy2': '11',
        'Cross_copy2': '12',
        'Empty_copy2': '13',
      });
      editor.undo();
      expect(_identities(editor.document), _once);
      editor.redo();
      expect(
        WordBookmarks.byName(editor.document, 'Cross_copy2')!.text,
        'Tail\nHead End',
      );
    },
  );

  test(
    'partial copy fails before replacing text or changing existing history',
    () async {
      final editor = _source();
      _at(editor, 3, 0);
      editor.insertText('Target');
      editor.insertText('?');
      editor.undo();
      editor.markClean();
      editor.caret
        ..paragraphIndex = 0
        ..logicalIndex = 16
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 0;
      await editor.copyToClipboard();
      editor.caret
        ..paragraphIndex = 3
        ..logicalIndex = 4
        ..selectionAnchorParagraph = 3
        ..selectionAnchor = 1;
      final paragraphs = editor.document.paragraphs.toList();
      final parts = _parts(editor.document);
      await expectLater(editor.pasteFromClipboard(), throwsStateError);
      expect(editor.document.paragraphs, orderedEquals(paragraphs));
      expect(paragraphs.last.text, 'Target');
      expect(_identities(editor.document), _original);
      expect(_parts(editor.document), parts);
      expect(editor.commands.canUndo, isTrue);
      expect(editor.commands.canRedo, isTrue);
      expect(editor.isDirty, isFalse);
      expect(
        (
          editor.caret.paragraphIndex,
          editor.caret.logicalIndex,
          editor.caret.selectionAnchorParagraph,
          editor.caret.selectionAnchor,
        ),
        (3, 4, 3, 1),
      );
    },
  );

  test('empty paste does not allocate bookmarks or create history', () async {
    final editor = _source();
    final parts = _parts(editor.document);
    OfficeClipboard.instance.clear();
    _at(editor, 3, 0);
    await editor.pasteFromClipboard();
    expect(_identities(editor.document), _original);
    expect(_parts(editor.document), parts);
    expect(editor.commands.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });

  test(
    'body copy history remains bound to its story after switching to header',
    () async {
      final editor = _source();
      final header = WmlParagraph(inlines: [WmlRun(text: 'Header')]);
      editor.document.sections.single.header.add(header);
      await _copy(editor);
      _at(editor, 3, 0);
      await editor.pasteFromClipboard();
      editor.beginHeaderFooterEdit(0, footer: false);
      editor.undo();
      expect(_identities(editor.document), _original);
      expect(header.text, 'Header');
      editor.redo();
      _checkCopy(editor.document);
      expect(header.text, 'Header');
    },
  );
}
