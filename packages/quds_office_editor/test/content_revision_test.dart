import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'pending note edits invalidate a captured save before their command commits',
    () async {
      final editor = WordEditorController(
        document: WmlDocument.empty(text: 'Body'),
      );
      addTearDown(editor.dispose);
      editor.insertFootnote(text: 'Original');
      final note = editor.document.footnotes.single;
      editor.commitNoteEdits();
      final captured = editor.contentRevision;
      var commands = 0;
      editor.commands.addListener(() => commands++);
      editor.setNoteText(note, 'Pending edit');
      expect(commands, 0);
      expect(editor.contentRevision, greaterThan(captured));
      final edited = editor.contentRevision;
      editor.setNoteText(note, 'Pending edit');
      expect(editor.contentRevision, edited);
      expect(commands, 0);

      // This is the host's save boundary: commit first, then capture revision.
      editor.commitNoteEdits();
      final savedRevision = editor.contentRevision;
      expect(commands, 1);
      final bytes = await editor.saveBytesAsync();
      expect(editor.contentRevision, savedRevision);
      expect(
        WordNotes.editableText(
          WordDeserializer().readBytes(bytes).footnotes.single,
        ),
        'Pending edit',
      );
      editor.markClean();
      expect(editor.contentRevision, savedRevision);
      expect(editor.isDirty, isFalse);
    },
  );

  test(
    'commands and history advance content revisions while caret and layout do not',
    () {
      final editor = WordEditorController(
        document: WmlDocument.empty(text: 'Body'),
      );
      addTearDown(editor.dispose);
      final initial = editor.contentRevision;
      editor.jumpToParagraph(0);
      editor.caret.logicalIndex = 1;
      editor.caret.collapseSelection();
      editor.relayout();
      editor.refresh();
      expect(editor.contentRevision, initial);
      editor.insertText('X');
      final inserted = editor.contentRevision;
      expect(inserted, greaterThan(initial));
      editor.undo();
      final undone = editor.contentRevision;
      expect(undone, greaterThan(inserted));
      editor.redo();
      expect(editor.contentRevision, greaterThan(undone));
    },
  );

  test('unchanged note-pane text does not create a false revision', () {
    final editor = WordEditorController(
      document: WmlDocument.empty(text: 'Body'),
    );
    addTearDown(editor.dispose);
    editor.insertFootnote(text: ' Space');
    final note = editor.document.footnotes.single;
    final initial = editor.contentRevision;
    expect(editor.noteEditText(note), 'Space');
    editor.setNoteText(note, editor.noteEditText(note));
    expect(note.paragraphs.single.text, ' Space');
    expect(editor.contentRevision, initial);
    editor.commitNoteEdits();
    expect(editor.contentRevision, initial);
  });

  test(
    'authored leading note whitespace advances revision and survives history',
    () async {
      final editor = WordEditorController(
        document: WmlDocument.empty(text: 'Body'),
      );
      addTearDown(editor.dispose);
      editor.insertFootnote(text: ' Space');
      final note = editor.document.footnotes.single;
      final initial = editor.contentRevision;
      expect(editor.noteEditText(note), 'Space');
      editor.setNoteText(note, ' Space');
      expect(note.paragraphs.single.text, '  Space');
      expect(editor.noteEditText(note), ' Space');
      expect(editor.contentRevision, greaterThan(initial));
      final bytes = await editor.saveBytesAsync();
      final reopened = WordDeserializer().readBytes(bytes).footnotes.single;
      expect(reopened.paragraphs.single.text, '  Space');
      expect(WordNotes.editableText(reopened), ' Space');
      editor.undo();
      expect(note.paragraphs.single.text, ' Space');
      expect(editor.noteEditText(note), 'Space');
      editor.redo();
      expect(note.paragraphs.single.text, '  Space');
      expect(editor.noteEditText(note), ' Space');
    },
  );

  test('note-pane split and history keep native bookmark endpoints', () async {
    final editor = WordEditorController.fromBytes(
      File(
        '../quds_office_engine/test/fixtures/fidelity/bookmarks.docx',
      ).readAsBytesSync(),
    );
    addTearDown(editor.dispose);
    final note = editor.document.footnotes.single;
    editor.setNoteText(note, 'Footnote\nRange');
    editor.commitNoteEdits();
    expect(note.paragraphs, hasLength(2));
    expect(
      note.paragraphs.first.inlines
          .whereType<WmlBookmarkBoundary>()
          .singleWhere((marker) => marker.isStart)
          .id,
      '40',
    );
    expect(
      note.paragraphs.last.inlines
          .whereType<WmlBookmarkBoundary>()
          .singleWhere((marker) => !marker.isStart)
          .id,
      '40',
    );
    editor.undo();
    expect(note.paragraphs.single.text, 'FootnoteRange');
    editor.redo();
    final reopened = WordDeserializer().readBytes(
      await editor.saveBytesAsync(),
    );
    expect(reopened.footnotes.single.paragraphs.map((p) => p.text), [
      'Footnote',
      'Range',
    ]);
    expect(
      reopened.footnotes.single.paragraphs.last.inlines
          .whereType<WmlBookmarkBoundary>()
          .singleWhere((marker) => !marker.isStart)
          .id,
      '40',
    );
  });
}
