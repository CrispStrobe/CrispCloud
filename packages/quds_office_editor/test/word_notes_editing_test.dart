import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _withNote() {
  final WordEditorController word = WordEditorController(
    document: WmlDocument.empty(text: 'Body'),
  );
  word.insertFootnote(text: 'Note body');
  return word;
}

void main() {
  test('note edits keep formatting and undo as one step', () {
    final WordEditorController word = _withNote();
    final WmlNote note = word.document.footnotes.single;
    note.paragraphs.first.inlines
      ..clear()
      ..add(WmlRun(text: 'Note body', properties: WmlRunProps(bold: true)));

    word.setNoteText(note, 'Note body!');
    word.setNoteText(note, 'Note body!!');
    word.commitNoteEdit(note);
    expect(word.noteEditText(note), 'Note body!!');
    expect(
      note.paragraphs.first.inlines.whereType<WmlRun>().every(
        (WmlRun r) => r.text.isEmpty || r.properties.bold,
      ),
      isTrue,
    );
    expect(word.isDirty, isTrue);

    word.undo();
    expect(word.noteEditText(note), 'Note body');
    word.redo();
    expect(word.noteEditText(note), 'Note body!!');
  });

  test('undo commits a pending note edit before undoing it', () {
    final WordEditorController word = _withNote();
    final WmlNote note = word.document.footnotes.single;
    word.setNoteText(note, 'Changed');
    word.undo();
    expect(word.noteEditText(note), 'Note body');
  });

  test('deleting a note removes its mark and undo restores both', () {
    final WordEditorController word = _withNote();
    final WmlNote note = word.document.footnotes.single;
    bool hasMark() => word.document.paragraphs.first.inlines.any(
      (WmlInline i) => i is WmlRun && i.noteRefId == note.id,
    );
    expect(hasMark(), isTrue);

    word.deleteNote(note);
    expect(word.document.footnotes, isEmpty);
    expect(hasMark(), isFalse);

    word.undo();
    expect(word.document.footnotes.single, same(note));
    expect(hasMark(), isTrue);
    expect(word.noteEditText(note), 'Note body');
  });

  testWidgets('the notes pane edits, adds and deletes notes', (tester) async {
    final WordEditorController word = _withNote();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 700,
            child: QudsWordEditor(
              controller: word,
              config: const OfficeSurfaceConfig(showNotesPane: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder field = find.byKey(const ValueKey<String>('notes-edit-1'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'Note body');

    await tester.enterText(field, 'Edited in the pane');
    await tester.pump();
    expect(
      word.noteEditText(word.document.footnotes.single),
      'Edited in the pane',
    );

    await tester.tap(find.byKey(const ValueKey<String>('notes-add-endnote')));
    await tester.pump();
    expect(word.document.endnotes, hasLength(1));
    expect(find.byKey(const ValueKey<String>('notes-edit-E1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('notes-delete-E1')));
    await tester.pump();
    expect(word.document.endnotes, isEmpty);
    expect(find.byKey(const ValueKey<String>('notes-edit-E1')), findsNothing);

    // Leaving the field committed the pane edit before the endnote was added,
    // so undo walks back: delete, add, then the pane edit. The field picks up
    // the restored text once it no longer has focus.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    word.undo();
    word.undo();
    expect(word.document.endnotes, isEmpty);
    word.undo();
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'Note body');
  });
}
