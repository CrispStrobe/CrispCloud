import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text, {String? bookmark}) => WmlParagraph(
  inlines: [WmlRun(text: text)],
  properties: WmlParagraphProps(bookmarkName: bookmark),
);

WordEditorController _controller(List<WmlParagraph> paragraphs) {
  final controller = WordEditorController(
    document: WmlDocument(
      sections: [
        WmlSection(blocks: <WmlBlock>[...paragraphs]),
      ],
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

void _at(WordEditorController controller, int paragraph, int offset) {
  controller.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = offset
    ..collapseSelection();
}

Future<OfficeClipboardPayload> _copyGenerated({
  bool leadingPlain = false,
}) async {
  final source = _controller([
    if (leadingPlain) _paragraph('Prefix'),
    _paragraph('Copied text', bookmark: 'Heading'),
  ]);
  source.caret
    ..paragraphIndex = leadingPlain ? 1 : 0
    ..logicalIndex = 'Copied text'.length
    ..selectionAnchorParagraph = 0
    ..selectionAnchor = 0;
  await source.copyToClipboard();
  final payload = OfficeClipboard.instance.local!;
  expect(
    (payload.wordBlocks.last as WmlParagraph).properties.bookmarkName,
    'Heading',
  );
  return payload;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => OfficeClipboard.instance.useSystem = false);
  tearDown(() {
    OfficeClipboard.instance.clear();
    OfficeClipboard.instance.useSystem = true;
  });

  for (final story in ['body', 'header', 'footer', 'comment']) {
    for (final leadingPlain in [false, true]) {
      if (story == 'body' && leadingPlain) continue;
      test(
        '$story rejects a generated bookmark property merge before any mutation${leadingPlain ? ' in a later paragraph' : ''}',
        () async {
          final payload = await _copyGenerated(leadingPlain: leadingPlain);
          final body = _paragraph('Body', bookmark: 'Heading');
          final editor = _controller([body]);
          _at(editor, 0, body.text.length);
          editor.insertText('+');
          editor.insertText('?');
          editor.undo();
          final target = story == 'body' ? body : _paragraph('Target');
          if (story == 'header' || story == 'footer') {
            final section = editor.document.sections.single;
            (story == 'header' ? section.header : section.footer).add(target);
            editor.beginHeaderFooterEdit(0, footer: story == 'footer');
          } else if (story == 'comment') {
            editor.document.comments.add(
              WmlComment(id: 7, paragraphs: [target]),
            );
            editor.beginCommentEdit(7);
          }
          editor.caret
            ..paragraphIndex = 0
            ..logicalIndex = 3
            ..selectionAnchorParagraph = 0
            ..selectionAnchor = 1;
          editor.markClean();
          final text = target.text;
          final inlines = [...target.inlines];
          final props = target.properties;
          final revision = editor.contentRevision;
          await expectLater(
            editor.pasteFromClipboard(),
            throwsUnsupportedError,
          );
          expect(target.text, text);
          expect(target.inlines, orderedEquals(inlines));
          expect(target.properties, same(props));
          expect(body.text, 'Body+');
          expect(WordBookmarks.generatedIds(editor.document).keys, ['Heading']);
          expect(editor.canUndo, isTrue);
          expect(editor.canRedo, isTrue);
          expect(editor.isDirty, isFalse);
          expect(editor.contentRevision, revision);
          expect(
            (
              editor.caret.paragraphIndex,
              editor.caret.logicalIndex,
              editor.caret.selectionAnchorParagraph,
              editor.caret.selectionAnchor,
            ),
            (0, 3, 0, 1),
          );
          expect(
            (payload.wordBlocks.last as WmlParagraph).properties.bookmarkName,
            'Heading',
          );
        },
      );
    }
  }

  for (final blankDocument in [false, true]) {
    test(
      'an empty ${blankDocument ? 'document' : 'target paragraph'} retains the generated bookmark and history',
      () async {
        await _copyGenerated();
        final target = _paragraph('');
        final existing = _paragraph('Existing', bookmark: 'Heading');
        final editor = _controller([if (!blankDocument) existing, target]);
        _at(editor, blankDocument ? 0 : 1, 0);
        await editor.pasteFromClipboard();
        final expected = blankDocument ? 'Heading' : 'Heading_copy';
        expect(
          WordBookmarks.textByName(editor.document, expected),
          'Copied text',
        );
        expect(editor.canUndo, isTrue);
        editor.undo();
        expect(editor.document.paragraphs.map((p) => p.text), [
          if (!blankDocument) 'Existing',
          '',
        ]);
        expect(WordBookmarks.textByName(editor.document, expected), isNull);
        editor.redo();
        expect(
          WordBookmarks.textByName(editor.document, expected),
          'Copied text',
        );
        for (int cycle = 0; cycle < 3; cycle++) {
          editor.loadBytes(await editor.saveBytesAsync());
          expect(
            WordBookmarks.byName(editor.document, expected)!.text,
            'Copied text',
          );
        }
      },
    );
  }

  test(
    'selection ending in an empty paragraph rejects before a retained prefix can lose the bookmark',
    () async {
      await _copyGenerated();
      final first = _paragraph('Keep target', bookmark: 'Heading');
      final last = _paragraph('');
      final editor = _controller([first, last]);
      editor.caret
        ..paragraphIndex = 1
        ..logicalIndex = 0
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 4;
      final inlines = [...first.inlines];
      await expectLater(editor.pasteFromClipboard(), throwsUnsupportedError);
      expect(editor.document.paragraphs, [same(first), same(last)]);
      expect(first.text, 'Keep target');
      expect(first.inlines, orderedEquals(inlines));
      expect(WordBookmarks.generatedIds(editor.document).keys, ['Heading']);
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
      expect(editor.contentRevision, 0);
      expect(
        (
          editor.caret.paragraphIndex,
          editor.caret.logicalIndex,
          editor.caret.selectionAnchorParagraph,
          editor.caret.selectionAnchor,
        ),
        (1, 0, 0, 4),
      );
    },
  );

  test('a later complete generated paragraph stays a separate block', () async {
    await _copyGenerated(leadingPlain: true);
    final editor = _controller([_paragraph('Target', bookmark: 'Heading')]);
    _at(editor, 0, 6);
    await editor.pasteFromClipboard();
    expect(editor.document.paragraphs.map((p) => p.text), [
      'TargetPrefix',
      'Copied text',
    ]);
    expect(
      WordBookmarks.textByName(editor.document, 'Heading_copy'),
      'Copied text',
    );
    editor.undo();
    expect(editor.document.paragraphs.single.text, 'Target');
    editor.redo();
    expect(
      WordBookmarks.textByName(editor.document, 'Heading_copy'),
      'Copied text',
    );
  });

  test(
    'native endpoint bookmarks still merge into a header with history',
    () async {
      final source = _controller([
        WmlParagraph(
          inlines: [
            WmlBookmarkBoundary(id: '1', isStart: true, name: 'Native'),
            WmlRun(text: 'Marked'),
            WmlBookmarkBoundary(id: '1', isStart: false),
          ],
        ),
      ]);
      source.caret
        ..paragraphIndex = 0
        ..logicalIndex = 6
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 0;
      await source.copyToClipboard();
      final editor = _controller([_paragraph('Body')]);
      final header = _paragraph('Header');
      editor.document.sections.single.header.add(header);
      editor.beginHeaderFooterEdit(0, footer: false);
      _at(editor, 0, 6);
      await editor.pasteFromClipboard();
      expect(header.text, 'HeaderMarked');
      expect(WordBookmarks.byName(editor.document, 'Native')!.text, 'Marked');
      editor.undo();
      expect(header.text, 'Header');
      expect(WordBookmarks.byName(editor.document, 'Native'), isNull);
      editor.redo();
      expect(WordBookmarks.byName(editor.document, 'Native')!.text, 'Marked');
    },
  );
}
