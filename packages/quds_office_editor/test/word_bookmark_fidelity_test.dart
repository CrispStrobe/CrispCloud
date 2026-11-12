import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _source() => WordEditorController.fromBytes(
  File(
    '../quds_office_engine/test/fixtures/fidelity/bookmarks.docx',
  ).readAsBytesSync(),
);

List<(String, bool, int, int)> _markers(WmlDocument document) {
  final out = <(String, bool, int, int)>[];
  var index = 0;
  for (final paragraph in document.paragraphs) {
    var offset = 0;
    for (final inline in paragraph.inlines) {
      if (inline is WmlRun) offset += inline.text.length;
      if (inline is WmlBookmarkMarker) {
        out.add((inline.id, inline.isStart, index, offset));
      }
    }
    index++;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native bookmark split, inside formatting and history keep exact endpoints',
    () async {
      final editor = _source();
      addTearDown(editor.dispose);
      final original = _markers(editor.document);
      editor.jumpToParagraph(1);
      editor.caret
        ..logicalIndex = 9
        ..selectionAnchorParagraph = 1
        ..selectionAnchor = 7;
      editor.applyRunFormat((properties) => properties.italic = true);
      expect(_markers(editor.document), original);
      editor.undo();
      expect(_markers(editor.document), original);
      editor.redo();
      editor.jumpToParagraph(1);
      editor.caret.logicalIndex = 8;
      editor.caret.collapseSelection();
      editor.insertParagraphBreak();
      expect(editor.document.paragraphs.elementAt(1).text, 'Alpha Be');
      expect(editor.document.paragraphs.elementAt(2).text, 'ta');
      final split = _markers(editor.document);
      expect(split.where((m) => m.$1 == '11'), [
        ('11', true, 1, 6),
        ('11', false, 2, 2),
      ]);
      editor.undo();
      expect(_markers(editor.document), original);
      editor.redo();
      expect(_markers(editor.document), split);
      editor.jumpToParagraph(2);
      editor.caret.logicalIndex = 1;
      editor.caret.collapseSelection();
      editor.insertText('+');
      final edited = _markers(editor.document);
      expect(edited.where((m) => m.$1 == '11'), [
        ('11', true, 1, 6),
        ('11', false, 2, 3),
      ]);
      editor.undo();
      expect(_markers(editor.document), split);
      editor.redo();
      for (var cycle = 1; cycle <= 3; cycle++) {
        final bytes = await editor.saveBytesAsync();
        final output = File(
          'build/fidelity-bookmarks/editor-bookmarks-$cycle.docx',
        );
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(bytes);
        editor.loadBytes(bytes);
        expect(_markers(editor.document), edited);
        expect(WordLink.paragraphIndexForAnchor(editor.document, 'Beta'), 1);
        final betaRuns = editor.document.paragraphs
            .elementAt(2)
            .inlines
            .whereType<WmlRun>();
        expect(betaRuns.map((run) => run.text).join(), 't+a');
        expect(betaRuns.every((run) => run.properties.bold), isTrue);
        expect(
          betaRuns.every((run) => run.properties.color == '345678'),
          isTrue,
        );
      }
    },
  );

  test(
    'native exact-range clipboard paste retains endpoints and source formatting',
    () async {
      final source = _source();
      final target = WordEditorController(
        document: WmlDocument.empty(text: 'Before After'),
      );
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      source.caret
        ..paragraphIndex = 1
        ..logicalIndex = 10
        ..selectionAnchorParagraph = 1
        ..selectionAnchor = 6;
      await source.copyToClipboard();
      target.caret.logicalIndex = 7;
      target.caret.collapseSelection();
      await target.pasteFromClipboard();
      expect(target.document.paragraphs.single.text, 'Before BetaAfter');
      expect(_markers(target.document), [
        ('11', true, 0, 7),
        ('11', false, 0, 11),
      ]);
      target.undo();
      expect(_markers(target.document), isEmpty);
      expect(target.document.paragraphs.single.text, 'Before After');
      target.redo();
      final saved = WordDeserializer().readBytes(await target.saveBytesAsync());
      expect(_markers(saved), [('11', true, 0, 7), ('11', false, 0, 11)]);
      expect(
        saved.paragraphs.single.inlines
            .whereType<WmlRun>()
            .singleWhere((run) => run.text == 'Beta')
            .properties
            .color,
        '345678',
      );
    },
  );

  test(
    'partial endpoint copy fails explicitly rather than exporting an invalid range',
    () async {
      final source = _source();
      final target = WordEditorController(
        document: WmlDocument.empty(text: 'Target'),
      );
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      source.caret
        ..paragraphIndex = 1
        ..logicalIndex = 3
        ..selectionAnchorParagraph = 1
        ..selectionAnchor = 0;
      await source.copyToClipboard();
      target.caret.logicalIndex = 6;
      target.caret.collapseSelection();
      await target.pasteFromClipboard();
      expect(() => WordSerializer().write(target.document), throwsStateError);
      target.undo();
      expect(target.document.paragraphs.single.text, 'Target');
      expect(_markers(target.document), isEmpty);
    },
  );
}
